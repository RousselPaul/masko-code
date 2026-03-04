import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) var appStore
    @Environment(AppUpdater.self) var appUpdater
    @State private var isHookEnabled = false
    @State private var hookError: String?
    @State private var showUninstallConfirm = false
    @State private var videoCacheSize: Int64 = 0
    @State private var ideExtensionInstalled = false
    @State private var ideStatuses: [ExtensionInstaller.IDEStatus] = []
    @AppStorage("ideExtensionEnabled") private var ideExtensionEnabled = true
    @State private var extensionError: String?
    @State private var extensionBusy = false
    @State private var installingIDE: String?  // command of IDE currently being installed

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Local Server")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appStore.localServer.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appStore.localServer.isRunning ? "Port \(appStore.localServer.port)" : "Offline")
                            .foregroundColor(Constants.textMuted)
                    }
                }
            } header: {
                Text("Connection").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                HStack {
                    Text("Events")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isHookEnabled ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(isHookEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(Constants.textMuted)
                    }
                }

                Button(action: toggleHooks) {
                    Text(isHookEnabled ? "Disable" : "Enable")
                        .foregroundColor(isHookEnabled ? Color(.sRGB, red: 220/255, green: 38/255, blue: 38/255) : Constants.orangePrimary)
                }
                .buttonStyle(.plain)

                if let error = hookError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            } header: {
                Text("Claude Code").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                HStack {
                    Text("Global Shortcuts")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appStore.hotkeyManager.isActive ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(appStore.hotkeyManager.isActive ? "Active" : "Needs Accessibility")
                            .foregroundColor(Constants.textMuted)
                    }
                }

                HStack {
                    Text("Focus Toggle")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    ShortcutRecorderView(hotkeyManager: appStore.hotkeyManager)
                }

                VStack(alignment: .leading, spacing: 4) {
                    shortcutRow("⌘1-9", "Accept Nth pending permission")
                    shortcutRow("Hold ⌘", "Show numbered badges on permissions")
                }
                .padding(.vertical, 2)

                if !appStore.hotkeyManager.isActive {
                    Button("Grant Accessibility Permission") {
                        appStore.hotkeyManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Constants.orangePrimary)
                }
            } header: {
                Text("Keyboard Shortcuts").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                // Per-IDE status list
                ForEach(ideStatuses) { ide in
                    HStack {
                        Text(ide.name)
                            .foregroundColor(ide.isDetected ? Constants.textPrimary : Constants.textMuted.opacity(0.5))
                        Spacer()
                        if ide.isInstalled {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text("Installed")
                                    .foregroundColor(Constants.textMuted)
                            }
                        } else if ide.isDetected {
                            if installingIDE == ide.command {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button {
                                    installExtension(command: ide.command)
                                } label: {
                                    Text("Install")
                                        .font(Constants.heading(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(Constants.orangePrimary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Text("Not detected")
                                .foregroundColor(Constants.textMuted.opacity(0.5))
                        }
                    }
                    .font(.system(size: 13))
                }

                // Actions
                if extensionBusy {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing...")
                            .font(.system(size: 12))
                            .foregroundColor(Constants.textMuted)
                        Spacer()
                    }
                } else if ideExtensionInstalled {
                    Toggle("Enable terminal switching", isOn: $ideExtensionEnabled)
                        .foregroundColor(Constants.textPrimary)
                    HStack(spacing: 12) {
                        Button(action: installExtension) {
                            Text("Reinstall")
                                .foregroundColor(Constants.orangePrimary)
                        }
                        .buttonStyle(.plain)
                        Button(action: uninstallExtension) {
                            Text("Uninstall")
                                .foregroundColor(Color(.sRGB, red: 220/255, green: 38/255, blue: 38/255))
                        }
                        .buttonStyle(.plain)
                    }
                } else if ideStatuses.contains(where: { $0.isDetected }) {
                    Text("Install the extension to jump to the exact terminal tab running Claude Code.")
                        .font(.system(size: 11))
                        .foregroundColor(Constants.textMuted)
                }

                if let error = extensionError {
                    Text(error).font(.system(size: 11)).foregroundColor(.red)
                }
            } header: {
                Text("IDE Integration").font(Constants.heading(size: 13, weight: .semibold))
            }
            .animation(.easeInOut(duration: 0.25), value: ideExtensionInstalled)
            .animation(.easeInOut(duration: 0.25), value: extensionBusy)

            Section {
                HStack {
                    Text("Events")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text("\(appStore.eventStore.events.count)")
                        .foregroundColor(Constants.textMuted)
                }
                HStack {
                    Text("Sessions")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text("\(appStore.sessionStore.sessions.count)")
                        .foregroundColor(Constants.textMuted)
                }
                HStack {
                    Text("Notifications")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text("\(appStore.notificationStore.notifications.count)")
                        .foregroundColor(Constants.textMuted)
                }
                HStack {
                    Text("Video Cache")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text(formatBytes(videoCacheSize))
                        .foregroundColor(Constants.textMuted)
                }
                Button(action: clearVideoCache) {
                    Text("Clear Video Cache")
                        .foregroundColor(Constants.orangePrimary)
                }
                .buttonStyle(.plain)
                .disabled(videoCacheSize == 0)

                HStack {
                    Text("Data Location")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text(LocalStorage.appSupportDir.path)
                        .font(.system(size: 10))
                        .foregroundColor(Constants.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Storage").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                if appUpdater.isAvailable {
                    @Bindable var updater = appUpdater
                    Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                        .foregroundColor(Constants.textPrimary)

                    Button(action: { appUpdater.checkForUpdates() }) {
                        Text("Check for Updates...")
                            .foregroundColor(Constants.orangePrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!appUpdater.canCheckForUpdates)
                } else {
                    Text("Updates unavailable (unsigned build)")
                        .font(.system(size: 12))
                        .foregroundColor(Constants.textMuted)
                }
            } header: {
                Text("Updates").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                HStack {
                    Text("Version")
                        .foregroundColor(Constants.textPrimary)
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundColor(Constants.textMuted)
                }
                Link(destination: URL(string: Constants.maskoBaseURL)!) {
                    HStack {
                        Text("Masko Website")
                            .foregroundColor(Constants.orangePrimary)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .foregroundColor(Constants.orangePrimary)
                            .font(.caption)
                    }
                }
            } header: {
                Text("About").font(Constants.heading(size: 13, weight: .semibold))
            }

            Section {
                Button(action: { showUninstallConfirm = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Uninstall Masko")
                    }
                    .foregroundColor(Color(.sRGB, red: 220/255, green: 38/255, blue: 38/255))
                }
                .buttonStyle(.plain)

                Text("Removes Claude Code hooks, local data, and quits the app.")
                    .font(.system(size: 11))
                    .foregroundColor(Constants.textMuted)
            } header: {
                Text("Uninstall").font(Constants.heading(size: 13, weight: .semibold))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Constants.lightBackground)
        .navigationTitle("Settings")
        .onAppear {
            isHookEnabled = HookInstaller.isRegistered()
            videoCacheSize = VideoCache.shared.cacheSize
            refreshIDEStatuses()
        }
        .alert("Uninstall Masko?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) { performUninstall() }
        } message: {
            Text("This will remove Claude Code hooks, delete all local data, and quit the app. You can reinstall anytime.")
        }
    }

    private func toggleHooks() {
        hookError = nil
        do {
            if isHookEnabled {
                try HookInstaller.uninstall()
            } else {
                try HookInstaller.install()
            }
            isHookEnabled = HookInstaller.isRegistered()
        } catch {
            hookError = error.localizedDescription
        }
    }

    private func clearVideoCache() {
        VideoCache.shared.clearCache()
        videoCacheSize = 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f MB", mb)
    }

    private func refreshIDEStatuses() {
        ideStatuses = ExtensionInstaller.allIDEStatuses()
        ideExtensionInstalled = ideStatuses.contains { $0.isInstalled }
    }

    private func installExtension() {
        extensionError = nil
        extensionBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ExtensionInstaller.install()
                let statuses = ExtensionInstaller.allIDEStatuses()
                DispatchQueue.main.async {
                    ideStatuses = statuses
                    ideExtensionInstalled = statuses.contains { $0.isInstalled }
                    ideExtensionEnabled = true
                    extensionBusy = false
                    ExtensionInstaller.triggerPermissionPrompt()
                }
            } catch {
                DispatchQueue.main.async {
                    extensionError = error.localizedDescription
                    extensionBusy = false
                }
            }
        }
    }

    private func installExtension(command: String) {
        extensionError = nil
        installingIDE = command
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ExtensionInstaller.install(command: command)
                let statuses = ExtensionInstaller.allIDEStatuses()
                DispatchQueue.main.async {
                    ideStatuses = statuses
                    ideExtensionInstalled = statuses.contains { $0.isInstalled }
                    ideExtensionEnabled = true
                    installingIDE = nil
                    ExtensionInstaller.triggerPermissionPrompt()
                }
            } catch {
                DispatchQueue.main.async {
                    extensionError = error.localizedDescription
                    installingIDE = nil
                }
            }
        }
    }

    private func uninstallExtension() {
        extensionError = nil
        extensionBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            ExtensionInstaller.uninstall()
            let statuses = ExtensionInstaller.allIDEStatuses()
            DispatchQueue.main.async {
                ideStatuses = statuses
                ideExtensionInstalled = false
                ideExtensionEnabled = false
                extensionBusy = false
            }
        }
    }

    private func performUninstall() {
        let fm = FileManager.default

        // 1. Remove hooks from ~/.claude/settings.json
        try? HookInstaller.uninstall()

        // 1.5. Remove IDE extension
        ExtensionInstaller.uninstall()

        // 2. Delete ~/.masko-desktop/ (hook script)
        let maskoDesktopDir = NSHomeDirectory() + "/.masko-desktop"
        try? fm.removeItem(atPath: maskoDesktopDir)

        // 3. Delete ~/Library/Application Support/masko-desktop/
        try? fm.removeItem(at: LocalStorage.appSupportDir)

        // 4. Delete ~/Library/Caches/masko-desktop/
        let cacheDir = VideoCache.shared.cacheDir.deletingLastPathComponent()
        try? fm.removeItem(at: cacheDir)

        // 5. Clear UserDefaults — all known bundle IDs (debug + release)
        for domain in ["com.masko.desktop", "masko-for-claude-code"] {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        UserDefaults.standard.synchronize()

        // 5.5. Delete preference plist files explicitly (macOS caches them)
        for plist in ["com.masko.desktop.plist", "masko-for-claude-code.plist", "masko-desktop.plist"] {
            let path = NSHomeDirectory() + "/Library/Preferences/" + plist
            try? fm.removeItem(atPath: path)
        }

        // 6. Quit the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Constants.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Constants.textMuted.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(Constants.textMuted)
        }
    }
}

// MARK: - Shortcut Recorder

/// A clickable view that records a keyboard shortcut when focused.
struct ShortcutRecorderView: View {
    var hotkeyManager: GlobalHotkeyManager
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press shortcut...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Constants.orangePrimary)
                } else {
                    Text(hotkeyManager.shortcutLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Constants.textPrimary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording ? Constants.orangePrimary.opacity(0.08) : Constants.textMuted.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Constants.orangePrimary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onKeyPress { press in
            guard isRecording else { return .ignored }

            // Build CGEventFlags from SwiftUI modifiers
            var flags: CGEventFlags = []
            if press.modifiers.contains(.command) { flags.insert(.maskCommand) }
            if press.modifiers.contains(.shift) { flags.insert(.maskShift) }
            if press.modifiers.contains(.control) { flags.insert(.maskControl) }
            if press.modifiers.contains(.option) { flags.insert(.maskAlternate) }

            // Require at least one modifier
            guard !flags.isEmpty else { return .ignored }

            // Map character to key code
            if let keyCode = characterToKeyCode(press.characters) {
                hotkeyManager.setShortcut(keyCode: keyCode, modifiers: flags)
                isRecording = false
                return .handled
            }
            return .ignored
        }
    }
}

/// Map a character string to a macOS key code.
private func characterToKeyCode(_ char: String) -> Int64? {
    let map: [String: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    return map[char.lowercased()]
}
