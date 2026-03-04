import SwiftUI
import AppKit
import CoreText
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeObserver: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar only — no dock icon
        NSApp.setActivationPolicy(.accessory)
        registerBundledFonts()
    }

    private func registerBundledFonts() {
        let fontNames = [
            "Fredoka-Regular", "Fredoka-Medium", "Fredoka-SemiBold", "Fredoka-Bold",
            "Rubik-Regular", "Rubik-Medium", "Rubik-SemiBold"
        ]
        for name in fontNames {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                continue
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App icon is set via CFBundleIconFile=AppIcon in Info.plist.
        // Do NOT set NSApp.applicationIconImage — it overrides the .icns
        // and causes incorrect sizing in the dock.

        // Show the dashboard window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AppDelegate.showDashboard()
        }
    }

    /// Dock icon click — reopen the dashboard window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.showDashboard()
        return true
    }

    /// Show the dashboard window
    static func showDashboard() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            // Disable minimize button — prevents minimize-to-dock
            window.styleMask.remove(.miniaturizable)
            window.makeKeyAndOrderFront(nil)

            // Observe close to go back to menu-bar-only mode
            // (Don't override window.delegate — SwiftUI needs it for environment propagation)
            let appDelegate = NSApp.delegate as? AppDelegate
            if appDelegate?.closeObserver == nil {
                appDelegate?.closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak appDelegate] _ in
                    appDelegate?.closeObserver = nil
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    /// When all windows close, go back to menu bar only
    func applicationDidResignActive(_ notification: Notification) {
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Observable wrapper around Sparkle's updater for SwiftUI environment injection.
/// Sparkle requires a valid code signature to operate — in unsigned debug builds
/// the updater is disabled gracefully (no error dialogs).
@Observable
final class AppUpdater {
    private var controller: SPUStandardUpdaterController?
    private(set) var isAvailable = false

    init() {
        // Only start Sparkle if the app is code-signed (release builds).
        // Unsigned builds will have no valid signature → Sparkle fails loudly.
        if Self.isCodeSigned {
            let ctrl = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller = ctrl
            isAvailable = true
        }
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Check if the running app bundle has a valid code signature.
    private static var isCodeSigned: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }
}

@main
struct MaskoDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appStore = AppStore()
    @State private var overlayManager = OverlayManager()
    @State private var appUpdater = AppUpdater()

    var body: some Scene {
        // Main dashboard window (shown on launch)
        WindowGroup {
            ContentView()
                .environment(appStore)
                .environment(overlayManager)
                .environment(appUpdater)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.light)
                .task {
                    guard !appStore.isRunning else { return }
                    overlayManager.sessionStore = appStore.sessionStore
                    overlayManager.eventStore = appStore.eventStore
                    overlayManager.pendingPermissionStore = appStore.pendingPermissionStore
                    overlayManager.hotkeyManager = appStore.hotkeyManager
                    appStore.onEventForOverlay = { [weak overlayManager] event in
                        overlayManager?.handleEvent(event)
                    }
                    appStore.onInputForOverlay = { [weak overlayManager] name, value in
                        overlayManager?.currentStateMachine?.setInput(name, value)
                    }
                    appStore.onRefreshOverlay = { [weak overlayManager] in
                        overlayManager?.refreshInputs()
                    }
                    await appStore.start()
                    overlayManager.restoreIfNeeded()
                }
        }
        .defaultSize(width: 1000, height: 700)

        // Menu bar — always visible, primary entry point
        MenuBarExtra {
            MenuBarView()
                .environment(appStore)
                .environment(overlayManager)
                .environment(appUpdater)
        } label: {
            if let url = Bundle.module.url(forResource: "logo", withExtension: "png", subdirectory: "Images"),
               let nsImage = NSImage(contentsOf: url) {
                let resized = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    nsImage.draw(in: rect)
                    return true
                }
                Image(nsImage: resized)
                if appStore.hasUnreadNotifications {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 6, y: -6)
                }
            } else {
                Image(systemName: appStore.hasUnreadNotifications ? "bell.badge" : "bell")
            }
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environment(appStore)
                .environment(overlayManager)
                .environment(appUpdater)
        }
    }

}
