import AppKit
import SwiftUI

/// NSHostingController subclass that supports transparent background
final class TransparentHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.layer?.masksToBounds = false
    }
}

/// Manages the floating mascot overlay panel lifecycle.
/// Uses two panels: a fixed-size mascot panel and a child HUD panel above it.
@MainActor
@Observable
final class OverlayManager {
    private(set) var isOverlayActive = false
    private(set) var currentURL: URL?
    private(set) var currentConfig: MaskoAnimationConfig?
    private(set) var currentStateMachine: OverlayStateMachine?
    private var panel: OverlayPanel?           // Mascot video — fixed size
    private var statsPanel: OverlayPanel?      // Stats/debug — fixed directly above mascot
    private var permissionPanel: OverlayPanel? // Permission prompts — smart-positioned
    private var permissionHUDConfig = PermissionHUDConfig()
    private var workspaceObservers: [NSObjectProtocol] = []

    // Snooze state
    private(set) var isSnoozed = false
    private(set) var snoozeEndDate: Date?
    private var snoozeTimer: Timer?
    private var snoozedConfig: MaskoAnimationConfig?

    // Context menu panel
    private var contextPanel: ContextMenuPanel?

    // Stores passed from AppStore for overlay display
    // Non-optional with defaults — avoids @Environment crash when overlay renders before stores are set
    var sessionStore: SessionStore = SessionStore()
    var eventStore: EventStore = EventStore()
    var pendingPermissionStore: PendingPermissionStore = PendingPermissionStore()
    var hotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager()

    var currentSizePixels: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: "overlay_size")
            return saved > 0 ? saved : OverlaySize.medium.rawValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "overlay_size")
            resizePanelToPixels(newValue)
        }
    }

    func showOverlay(url: URL) {
        // If same URL already active, just re-assert
        if panel != nil, currentURL == url {
            reassertPanel()
            isOverlayActive = true
            return
        }

        // Close existing
        hideOverlay()

        let px = currentSizePixels
        let size = CGSize(width: px, height: px)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        // Restore position or default to bottom-right
        let savedX = UserDefaults.standard.double(forKey: "overlay_x")
        let savedY = UserDefaults.standard.double(forKey: "overlay_y")
        let origin: CGPoint
        if savedX > 0 || savedY > 0 {
            origin = CGPoint(x: savedX, y: savedY)
        } else {
            origin = CGPoint(
                x: screenFrame.maxX - size.width - 40,
                y: screenFrame.minY + 40
            )
        }

        let rect = NSRect(origin: origin, size: size)
        let newPanel = OverlayPanel(contentRect: rect)

        let view = OverlayMascotView(
            url: url,
            onClose: { [weak self] in self?.hideOverlay() },
            onResize: { [weak self] newSize in self?.currentSizePixels = newSize.rawValue },
            onDragResize: { [weak self] size in self?.resizePanelLive(size) },
            onDragResizeEnd: { [weak self] size in self?.currentSizePixels = size },
            onSnooze: { [weak self] minutes in self?.snooze(minutes: minutes) }
        )

        let controller = TransparentHostingController(rootView: view)
        newPanel.contentView = controller.view
        newPanel.contentViewController = controller

        // Right-click handler
        newPanel.onRightClick = { [weak self] point in self?.showContextMenu(at: point) }

        // Show without stealing focus
        newPanel.orderFrontRegardless()

        // Move into a system-level Space that doesn't participate in Space swipe animations
        SkyLightOperator.shared.delegateWindow(newPanel)

        print("[masko-desktop] Overlay panel shown at \(rect), level=\(newPanel.level.rawValue)")

        self.panel = newPanel
        self.currentURL = url
        self.isOverlayActive = true

        // Save URL for restore on relaunch
        UserDefaults.standard.set(url.absoluteString, forKey: "overlay_url")

        setupObservers(for: newPanel)
    }

    /// Show overlay using a canvas config with a full state machine.
    /// Creates two panels: mascot (fixed) + HUD (child, above).
    func showOverlayWithConfig(_ config: MaskoAnimationConfig) {
        // Cancel any active snooze
        cancelSnooze()

        // Close existing
        hideOverlay()

        self.currentConfig = config

        // Pre-download all videos immediately (fire and forget)
        Task { await VideoCache.shared.preload(config: config) }

        // Save config JSON for restore on relaunch
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "overlay_config")
        }

        // Create state machine
        let sm = OverlayStateMachine(config: config)
        self.currentStateMachine = sm
        sm.start()

        // --- Mascot panel (fixed size, just the video) ---
        let px = currentSizePixels
        let size = CGSize(width: px, height: px)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        let savedX = UserDefaults.standard.double(forKey: "overlay_x")
        let savedY = UserDefaults.standard.double(forKey: "overlay_y")
        let origin: CGPoint
        if savedX > 0 || savedY > 0 {
            origin = CGPoint(x: savedX, y: savedY)
        } else {
            origin = CGPoint(
                x: screenFrame.maxX - size.width - 40,
                y: screenFrame.minY + 40
            )
        }

        let mascotRect = NSRect(origin: origin, size: size)
        let mascotPanel = OverlayPanel(contentRect: mascotRect)

        let mascotView = OverlayStateMachineView(
            stateMachine: sm,
            onClose: { [weak self] in self?.hideOverlay() },
            onResize: { [weak self] newSize in self?.currentSizePixels = newSize.rawValue },
            onDragResize: { [weak self] size in self?.resizePanelLive(size) },
            onDragResizeEnd: { [weak self] size in self?.currentSizePixels = size },
            onSnooze: { [weak self] minutes in self?.snooze(minutes: minutes) }
        )

        let mascotController = TransparentHostingController(rootView: mascotView)
        mascotPanel.contentView = mascotController.view
        mascotPanel.contentViewController = mascotController

        // Right-click handler
        mascotPanel.onRightClick = { [weak self] point in self?.showContextMenu(at: point) }

        mascotPanel.orderFrontRegardless()
        SkyLightOperator.shared.delegateWindow(mascotPanel)

        // --- Stats panel (fixed directly above mascot) ---
        let statsView = StatsHUDView(stateMachine: sm)
            .environment(sessionStore)
            .environment(pendingPermissionStore)

        let statsWidth = max(size.width, 180)
        let statsController = TransparentHostingController(rootView: statsView)
        let statsHeight = max(statsController.view.fittingSize.height, 20)
        let statsRect = NSRect(
            x: mascotRect.midX - statsWidth / 2,
            y: mascotRect.maxY + 4,
            width: statsWidth,
            height: statsHeight
        )
        let newStatsPanel = OverlayPanel(contentRect: statsRect)
        newStatsPanel.isMovableByWindowBackground = false

        newStatsPanel.contentView = statsController.view
        newStatsPanel.contentViewController = statsController

        newStatsPanel.orderFrontRegardless()
        SkyLightOperator.shared.delegateWindow(newStatsPanel)
        mascotPanel.addChildWindow(newStatsPanel, ordered: .above)

        // --- Permission panel (smart-positioned, adapts to screen edges) ---
        permissionHUDConfig = PermissionHUDConfig()
        permissionHUDConfig.onContentSizeChange = { [weak self] _ in
            self?.syncPermissionPanel()
        }
        let permView = PermissionHUDView(config: permissionHUDConfig)
            .environment(pendingPermissionStore)
            .environment(hotkeyManager)

        let permController = TransparentHostingController(rootView: permView)
        permController.sizingOptions = []

        let statsTop = statsRect.maxY
        let permRect = NSRect(
            x: mascotRect.midX - 140,
            y: statsTop + 4,
            width: 280,
            height: 200
        )
        let newPermPanel = OverlayPanel(contentRect: permRect)
        newPermPanel.isMovableByWindowBackground = false
        newPermPanel.contentView = permController.view
        newPermPanel.contentViewController = permController

        // Resize/reposition when permissions change (delay lets SwiftUI render)
        pendingPermissionStore.onPendingChange = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.syncPermissionPanel()
            }
        }

        // Activate app + make permission panel key when a text-input field needs focus
        pendingPermissionStore.onRequestTextInputFocus = { [weak self] in
            guard let permPanel = self?.permissionPanel else { return }
            NSApp.activate(ignoringOtherApps: true)
            permPanel.makeKey()
        }

        newPermPanel.orderFrontRegardless()
        SkyLightOperator.shared.delegateWindow(newPermPanel)
        mascotPanel.addChildWindow(newPermPanel, ordered: .above)

        print("[masko-desktop] State machine overlay: mascot=\(mascotRect), stats+perm panels")

        self.panel = mascotPanel
        self.statsPanel = newStatsPanel
        self.permissionPanel = newPermPanel
        self.isOverlayActive = true

        setupObservers(for: mascotPanel)

        // Also reposition HUD when mascot moves (child windows move together,
        // but we need to keep the HUD anchored to the top)
        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: mascotPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionHUD() }
        }
        workspaceObservers.append(moveObserver)
    }

    /// Recompute aggregate session state and push inputs to the state machine.
    /// Can be called independently (e.g. after interrupt detection) without needing an event.
    func refreshInputs() {
        guard let sm = currentStateMachine else { return }

        let active = sessionStore.activeSessions
        let isWorking = active.contains { $0.phase == .running }
        let isIdle = active.allSatisfy { $0.phase == .idle } || active.isEmpty
        let isAlert = pendingPermissionStore.count > 0
        let isCompacting = active.contains { $0.isCompacting }
        let sessionCount = active.count

        sm.setInput("claudeCode::isWorking", .bool(isWorking))
        sm.setInput("claudeCode::isIdle", .bool(isIdle))
        sm.setInput("claudeCode::isAlert", .bool(isAlert))
        sm.setInput("claudeCode::isCompacting", .bool(isCompacting))
        sm.setInput("claudeCode::sessionCount", .number(Double(sessionCount)))
    }

    /// Compute aggregate session state and push inputs to the state machine.
    /// Called after SessionStore.recordEvent() has already updated session phases.
    func handleEvent(_ event: ClaudeEvent) {
        refreshInputs()

        // Fire granular event trigger (auto-resets after transition)
        guard let sm = currentStateMachine else { return }
        let eventInput = "claudeCode::\(event.hookEventName)"
        sm.setInput(eventInput, .bool(true))
    }

    /// Temporarily hide the overlay and restore it after the given duration.
    /// Pass `minutes: 0` for indefinite snooze (until manually woken).
    func snooze(minutes: Int) {
        guard isOverlayActive, let config = currentConfig else { return }
        snoozedConfig = config

        let endDate: Date
        if minutes > 0 {
            endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            endDate = .distantFuture // indefinite
        }
        snoozeEndDate = endDate
        isSnoozed = true

        // Persist snooze state
        UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: "snooze_end_date")

        // Show toast before hiding
        showSnoozeToast(minutes: minutes)

        // Hide overlay but keep config in UserDefaults for restore
        hideOverlay(clearConfig: false)

        // Schedule auto-restore (only for timed snooze)
        if minutes > 0 {
            snoozeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.wakeFromSnooze()
                }
            }
        }
    }

    /// Cancel snooze and restore the overlay immediately.
    func wakeFromSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        let config = snoozedConfig
        snoozedConfig = nil
        snoozeEndDate = nil
        isSnoozed = false
        UserDefaults.standard.removeObject(forKey: "snooze_end_date")

        if let config {
            showOverlayWithConfig(config)
        }
    }

    func hideOverlay(clearConfig: Bool = true) {
        // Remove all observers
        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        dismissContextMenu()
        permissionPanel?.close()
        permissionPanel = nil
        statsPanel?.close()
        statsPanel = nil
        panel?.close()
        panel = nil
        currentURL = nil
        currentConfig = nil
        currentStateMachine = nil
        isOverlayActive = false

        if clearConfig {
            UserDefaults.standard.removeObject(forKey: "overlay_url")
            UserDefaults.standard.removeObject(forKey: "overlay_config")
        }
    }

    func toggleOverlay() {
        if isOverlayActive {
            hideOverlay()
        } else if let urlString = UserDefaults.standard.string(forKey: "overlay_url"),
                  let url = URL(string: urlString) {
            showOverlay(url: url)
        }
    }

    /// Restore overlay from previous session
    func restoreIfNeeded() {
        // Check if we're in a snooze period
        let snoozeEndTimestamp = UserDefaults.standard.double(forKey: "snooze_end_date")
        if snoozeEndTimestamp > 0 {
            let endDate = Date(timeIntervalSince1970: snoozeEndTimestamp)
            if endDate > Date() {
                // Still snoozed — restore config but stay hidden
                if let configData = UserDefaults.standard.data(forKey: "overlay_config"),
                   let config = try? JSONDecoder().decode(MaskoAnimationConfig.self, from: configData) {
                    snoozedConfig = config
                    snoozeEndDate = endDate
                    isSnoozed = true

                    // Schedule wake for remaining time (skip for indefinite)
                    if endDate != .distantFuture {
                        let remaining = endDate.timeIntervalSinceNow
                        snoozeTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.wakeFromSnooze()
                            }
                        }
                    }
                }
                return
            } else {
                // Snooze expired while app was closed — clear it
                UserDefaults.standard.removeObject(forKey: "snooze_end_date")
            }
        }

        // Config-based overlay (state machine) takes priority
        if let configData = UserDefaults.standard.data(forKey: "overlay_config"),
           let config = try? JSONDecoder().decode(MaskoAnimationConfig.self, from: configData) {
            showOverlayWithConfig(config)
            return
        }
        // Fall back to URL-based overlay (single video loop)
        guard let urlString = UserDefaults.standard.string(forKey: "overlay_url"),
              let url = URL(string: urlString) else { return }
        showOverlay(url: url)
    }

    // MARK: - Private

    private func cancelSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozedConfig = nil
        snoozeEndDate = nil
        isSnoozed = false
        UserDefaults.standard.removeObject(forKey: "snooze_end_date")
    }

    // MARK: - Context Menu

    func showContextMenu(at point: NSPoint) {
        dismissContextMenu()
        let panel = ContextMenuPanel()
        let content = OverlayContextMenuContent(
            onSnooze: { [weak self] minutes in self?.snooze(minutes: minutes) },
            onResize: { [weak self] size in self?.currentSizePixels = size.rawValue },
            onClose: { [weak self] in self?.hideOverlay() },
            dismiss: { [weak panel] in panel?.dismiss() }
        )
        panel.showAt(point: point, mascotFrame: self.panel?.frame, with: content)
        self.contextPanel = panel
    }

    func dismissContextMenu() {
        contextPanel?.dismiss()
        contextPanel = nil
    }

    // MARK: - Snooze Toast

    private func showSnoozeToast(minutes: Int) {
        guard let mascotPanel = panel else { return }
        let mascotFrame = mascotPanel.frame

        let message: String
        if minutes == 0 {
            message = "Snoozed"
        } else if minutes < 60 {
            message = "Snoozed for \(minutes) min"
        } else {
            message = "Snoozed for \(minutes / 60) hour\(minutes >= 120 ? "s" : "")"
        }

        let toastView = Text(message)
            .font(Constants.heading(size: 13, weight: .medium))
            .foregroundStyle(Constants.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Constants.surfaceWhite)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadiusSmall)
                    .stroke(Constants.border, lineWidth: 1)
            )
            .shadow(color: Constants.cardShadowColor, radius: 4, x: 0, y: 2)

        let toastPanel = OverlayPanel(contentRect: NSRect(
            x: mascotFrame.midX - 80,
            y: mascotFrame.midY - 16,
            width: 160,
            height: 32
        ))
        toastPanel.isMovableByWindowBackground = false

        let controller = TransparentHostingController(rootView: toastView)
        toastPanel.contentView = controller.view
        toastPanel.contentViewController = controller

        // Size to fit
        let fittingSize = controller.view.fittingSize
        toastPanel.setFrame(NSRect(
            x: mascotFrame.midX - fittingSize.width / 2,
            y: mascotFrame.midY - fittingSize.height / 2,
            width: fittingSize.width,
            height: fittingSize.height
        ), display: true)

        toastPanel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            toastPanel.close()
        }
    }

    /// Re-apply window level and bring to front without stealing focus.
    private func reassertPanel() {
        guard let panel else { return }
        panel.level = .screenSaver
        panel.orderFrontRegardless()
        if let statsPanel {
            statsPanel.level = .screenSaver
            statsPanel.orderFrontRegardless()
        }
        if let permissionPanel {
            permissionPanel.level = .screenSaver
            permissionPanel.orderFrontRegardless()
        }
    }

    private func resizePanelToPixels(_ pixels: Int) {
        guard let panel else { return }
        let side = CGFloat(pixels)
        let frame = panel.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (side - frame.height),
            width: side,
            height: side
        )
        panel.setFrame(newFrame, display: true, animate: true)
        repositionHUD()
    }

    /// Resize panel instantly during drag — no animation, no UserDefaults save.
    func resizePanelLive(_ pixels: Int) {
        guard let panel else { return }
        let side = CGFloat(pixels)
        let frame = panel.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (side - frame.height),
            width: side,
            height: side
        )
        // Kill all implicit animations for instant feedback
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(newFrame, display: true, animate: false)
        repositionHUD()
        CATransaction.commit()
    }

    /// Position stats panel directly above mascot (fixed, never adapts).
    private func repositionStats() {
        guard let panel, let statsPanel else { return }
        let mascotFrame = panel.frame
        let statsSize = statsPanel.frame.size

        let x = mascotFrame.midX - statsSize.width / 2
        let y = mascotFrame.maxY + 4
        statsPanel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    /// Measure permission content, resize panel, and smart-position it.
    /// Tries above → right → left → below mascot.
    private func syncPermissionPanel() {
        guard let panel, let permissionPanel else { return }

        let contentSize = permissionHUDConfig.contentSize
        if contentSize.height <= 10 { return }
        let permSize = CGSize(width: max(contentSize.width, 280), height: contentSize.height)

        let mascotFrame = panel.frame
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let gap: CGFloat = 4
        let statsTop = statsPanel?.frame.maxY ?? mascotFrame.maxY

        var origin = CGPoint.zero
        var tailSide: TailSide = .bottom
        var tailPercent: CGFloat = 0.80

        // 1. ABOVE (preferred) — directly above stats panel
        let aboveY = statsTop + gap
        if aboveY + permSize.height <= screen.maxY {
            origin = CGPoint(
                x: max(screen.minX, min(mascotFrame.midX - permSize.width / 2, screen.maxX - permSize.width)),
                y: aboveY
            )
            tailSide = .bottom
            tailPercent = (mascotFrame.midX - origin.x) / permSize.width
        }
        // 2. RIGHT
        else {
            let rightX = mascotFrame.maxX + gap
            if rightX + permSize.width <= screen.maxX {
                let y = max(screen.minY, min(statsTop - permSize.height, screen.maxY - permSize.height))
                origin = CGPoint(x: rightX, y: y)
                tailSide = .left
                tailPercent = 1.0 - ((mascotFrame.midY - origin.y) / permSize.height)
            }
            // 3. LEFT
            else {
                let leftX = mascotFrame.minX - permSize.width - gap
                if leftX >= screen.minX {
                    let y = max(screen.minY, min(statsTop - permSize.height, screen.maxY - permSize.height))
                    origin = CGPoint(x: leftX, y: y)
                    tailSide = .right
                    tailPercent = 1.0 - ((mascotFrame.midY - origin.y) / permSize.height)
                }
                // 4. BELOW (fallback)
                else {
                    let belowY = mascotFrame.minY - permSize.height - gap
                    origin = CGPoint(
                        x: max(screen.minX, min(mascotFrame.midX - permSize.width / 2, screen.maxX - permSize.width)),
                        y: max(screen.minY, belowY)
                    )
                    tailSide = .top
                    tailPercent = (mascotFrame.midX - origin.x) / permSize.width
                }
            }
        }

        // Clamp tail percent
        tailPercent = max(0.15, min(tailPercent, 0.85))

        permissionPanel.setFrame(NSRect(origin: origin, size: permSize), display: true)
        permissionHUDConfig.tailSide = tailSide
        permissionHUDConfig.tailPercent = tailPercent
    }

    /// Reposition all HUD panels.
    private func repositionHUD() {
        repositionStats()
        syncPermissionPanel()
    }

    private func savePosition() {
        guard let panel else { return }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "overlay_x")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "overlay_y")
    }

    private func setupObservers(for targetPanel: OverlayPanel) {
        // Observe position changes to persist
        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: targetPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.savePosition() }
        }
        workspaceObservers.append(moveObserver)

        // Re-assert panel when switching Spaces
        let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reassertPanel() }
        }
        workspaceObservers.append(spaceObserver)

        // Re-assert panel when another app activates (Cmd+Tab)
        let appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reassertPanel() }
        }
        workspaceObservers.append(appObserver)
    }
}
