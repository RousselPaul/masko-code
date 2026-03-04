import AppKit
import Foundation

@Observable
final class AppStore {
    let localServer = LocalServer()
    let eventStore = EventStore()
    let sessionStore = SessionStore()
    let notificationStore = NotificationStore()
    let notificationService = NotificationService.shared
    let pendingPermissionStore = PendingPermissionStore()
    let mascotStore = MascotStore()
    let hotkeyManager = GlobalHotkeyManager()

    private(set) var eventProcessor: EventProcessor!
    private(set) var isReady = false
    private(set) var isRunning = false

    /// Called when a Claude Code event is received — wire to OverlayManager.handleEvent
    var onEventForOverlay: ((ClaudeEvent) -> Void)?
    /// Called when a custom input is received via POST /input
    var onInputForOverlay: ((String, ConditionValue) -> Void)?
    /// Called when session phases change outside of events (e.g. interrupt detection via transcript)
    var onRefreshOverlay: (() -> Void)?

    var hasUnreadNotifications: Bool { notificationStore.unreadCount > 0 }

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        self.eventProcessor = EventProcessor(
            eventStore: eventStore,
            sessionStore: sessionStore,
            notificationStore: notificationStore,
            notificationService: notificationService
        )

        // Wire local server → event processor + overlay state machine
        localServer.onEventReceived = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.eventProcessor.process(event)

                // If a subsequent event arrives for a session with pending permissions,
                // the user resolved the permission from the terminal — dismiss the overlay.
                // PermissionRequest events have toolUseId=nil, so we match by sessionId only.
                if let eventType = event.eventType,
                   let sid = event.sessionId,
                   [.postToolUse, .postToolUseFailure, .stop, .userPromptSubmit].contains(eventType),
                   self.pendingPermissionStore.pending.contains(where: { $0.event.sessionId == sid }) {
                    self.pendingPermissionStore.dismissForSession(sid)
                }

                self.onEventForOverlay?(event)
            }
        }

        // Wire local server → custom input endpoint
        localServer.onInputReceived = { [weak self] name, value in
            guard let self else { return }
            Task { @MainActor in
                self.onInputForOverlay?(name, value)
            }
        }

        // Wire local server → permission requests (hold connection for user decision)
        localServer.onPermissionRequest = { [weak self] event, connection in
            guard let self else { return }
            Task { @MainActor in
                self.pendingPermissionStore.add(event: event, connection: connection)
            }
        }

        // Wire interrupt detection → overlay refresh
        sessionStore.onPhasesChanged = { [weak self] in
            self?.onRefreshOverlay?()
        }

        // Wire pending permission count → hotkey manager
        pendingPermissionStore.onPendingCountChange = { [weak self] in
            guard let self else { return }
            self.hotkeyManager.hasPendingPermissions = !self.pendingPermissionStore.pending.isEmpty
        }

        // Wire hotkey manager — ⌘N selects Nth button within topmost card
        hotkeyManager.onSelectPermission = { [weak self] index in
            guard let self else { return }
            guard !self.pendingPermissionStore.pending.isEmpty else { return }
            if self.hotkeyManager.selectedButtonIndex == index {
                self.hotkeyManager.selectedButtonIndex = nil
            } else {
                self.hotkeyManager.selectedButtonIndex = index
            }
        }

        // Wire hotkey manager — ⌘Enter confirms the selected button
        hotkeyManager.onConfirmPermission = { [weak self] in
            guard let self else { return }
            self.hotkeyManager.confirmTrigger += 1
        }

        // Wire hotkey manager — ⌘Esc dismisses (denies) topmost permission
        hotkeyManager.onDismissPermission = { [weak self] in
            guard let self else { return }
            let reversed = Array(self.pendingPermissionStore.pending.reversed())
            guard let topPerm = reversed.first else { return }
            self.pendingPermissionStore.resolve(id: topPerm.id, decision: .deny)
        }

        // Wire hotkey manager — toggle focus via configurable shortcut
        // When permissions are pending, ⌘M focuses the terminal (same as terminal button).
        // When no permissions, toggles the dashboard window.
        hotkeyManager.onToggleFocus = { [weak self] in
            guard let self else { return }
            let reversed = Array(self.pendingPermissionStore.pending.reversed())
            if let topPerm = reversed.first {
                IDETerminalFocus.focus(
                    terminalPid: topPerm.event.terminalPid,
                    shellPid: topPerm.event.shellPid
                )
            } else {
                self.hotkeyManager.toggleFocus()
            }
        }

        // Update permission notification with resolution outcome
        pendingPermissionStore.onResolved = { [weak self] event, outcome in
            guard let self else { return }
            for notification in self.notificationStore.notifications where
                notification.resolutionOutcome == .pending &&
                notification.category == .permissionRequest &&
                notification.sessionId == event.sessionId {
                self.notificationStore.updateResolution(notification.id, outcome: outcome)
                break
            }
        }
    }

    /// Call once from .task {} on the menu bar view
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        do {
            try HookInstaller.install()
        } catch {
            print("[masko-desktop] Failed to install hooks: \(error)")
        }

        // Start global hotkey manager (CGEvent tap)
        hotkeyManager.start()

        // Evict cached videos older than 30 days
        VideoCache.shared.evictStaleFiles()

        await notificationService.requestPermission()

        do {
            try localServer.start()
        } catch {
            print("[masko-desktop] Failed to start local server: \(error)")
        }

        // Reconcile sessions when app comes to foreground (crash recovery)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionStore.reconcileIfNeeded()
            // Retry hotkey manager if not yet active (user may have just granted Accessibility)
            if !(self?.hotkeyManager.isActive ?? true) {
                self?.hotkeyManager.start()
            }
        }

        // Clean up on app termination to avoid zombie NWListener processes
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }

        isReady = true
    }

    /// Tear down server and timers to prevent zombie processes
    func stop() {
        localServer.stop()
        sessionStore.stopTimers()
        pendingPermissionStore.stopTimers()
        hotkeyManager.stop()
    }
}
