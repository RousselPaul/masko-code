import SwiftUI
import ApplicationServices

struct OnboardingView: View {
    @Environment(AppStore.self) var appStore
    @Environment(OverlayManager.self) var overlayManager

    let onComplete: () -> Void

    @State private var step = 0
    @State private var hookInstalled = false
    @State private var hookError: String?
    @State private var ideExtensionInstalled = false
    @State private var ideExtensionError: String?
    @State private var accessibilityGranted = false
    @State private var mascotActivated = false
    @State private var selectedPresetSlug: String? = nil
    @State private var isLoadingPreset = false

    private let totalSteps = 6

    /// Advance to the next step that actually needs user action, skipping already-completed ones.
    private func nextStep(after current: Int) {
        var next = current + 1
        // Skip hooks step if already installed
        if next == 1 && hookInstalled { next = 2 }
        // Skip accessibility step if already granted
        if next == 3 && AXIsProcessTrusted() { next = 4 }
        // Skip IDE step if no IDE detected
        if next == 4 && ExtensionInstaller.availableIDEs().isEmpty { next = 5 }
        // Step 2 (notifications) and 5 (mascot) always show
        step = min(next, totalSteps - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: hooksStep
                case 2: notificationsStep
                case 3: accessibilityStep
                case 4: ideIntegrationStep
                case 5: mascotStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: 440)
            .transition(.opacity)
            .id(step)

            Spacer()

            // Step indicator dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Constants.orangePrimary : Constants.border)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.lightBackground)
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            hookInstalled = HookInstaller.isRegistered()
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            if let url = Bundle.module.url(forResource: "logo", withExtension: "png", subdirectory: "Images"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 4) {
                Text("Welcome to Masko")
                    .font(Constants.heading(size: 28, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)
                Text("for Claude Code")
                    .font(Constants.heading(size: 18, weight: .semibold))
                    .foregroundStyle(Constants.textMuted)
            }

            Text("Masko lives on your screen, reacts to Claude Code activity, and lets you approve actions without switching windows.")
                .font(Constants.body(size: 14))
                .foregroundStyle(Constants.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            primaryButton("Get Started") {
                nextStep(after: 0)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Step 1: Enable Hooks

    private var hooksStep: some View {
        VStack(spacing: 20) {
            stepIcon(hookInstalled ? "checkmark.circle.fill" : "terminal.fill",
                     color: hookInstalled ? .green : Constants.orangePrimary)

            VStack(spacing: 8) {
                Text("Connect to Claude Code")
                    .font(Constants.heading(size: 24, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)

                Text("Masko listens to Claude Code events via hooks. This adds a small config to ~/.claude/settings.json.")
                    .font(Constants.body(size: 14))
                    .foregroundStyle(Constants.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if let error = hookError {
                Text(error)
                    .font(Constants.body(size: 12))
                    .foregroundStyle(.red)
            }

            if hookInstalled {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Hooks enabled")
                        .font(Constants.body(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                }

                primaryButton("Continue") {
                    nextStep(after: 1)
                }
            } else {
                primaryButton("Enable Hooks") {
                    enableHooks()
                }

                skipButton { nextStep(after: 1) }
            }
        }
    }

    // MARK: - Step 2: Notifications

    private var notificationsStep: some View {
        VStack(spacing: 20) {
            stepIcon("bell.fill", color: Constants.orangePrimary)

            VStack(spacing: 8) {
                Text("Stay in the loop")
                    .font(Constants.heading(size: 24, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)

                Text("Get notified when Claude Code needs your attention \u{2014} permission requests, questions, and completed tasks.")
                    .font(Constants.body(size: 14))
                    .foregroundStyle(Constants.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            primaryButton("Enable Notifications") {
                Task {
                    await appStore.notificationService.requestPermission()
                    nextStep(after: 2)
                }
            }

            skipButton { nextStep(after: 2) }
        }
    }

    // MARK: - Step 3: Accessibility (Keyboard Shortcuts)

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            stepIcon(accessibilityGranted ? "checkmark.circle.fill" : "keyboard.fill",
                     color: accessibilityGranted ? .green : Constants.orangePrimary)

            VStack(spacing: 8) {
                Text("Keyboard shortcuts")
                    .font(Constants.heading(size: 24, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)

                Text("Accept permissions with \u{2318}1, toggle focus with \u{2318}\u{21E7}M \u{2014} without switching windows.")
                    .font(Constants.body(size: 14))
                    .foregroundStyle(Constants.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            if accessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Accessibility enabled")
                        .font(Constants.body(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                }

                primaryButton("Continue") {
                    nextStep(after: 3)
                }
            } else {
                primaryButton("Enable Shortcuts") {
                    enableAccessibility()
                }

                skipButton { nextStep(after: 3) }
            }
        }
    }

    // MARK: - Step 4: IDE Integration (optional, skipped if no IDEs)

    private var ideIntegrationStep: some View {
        VStack(spacing: 20) {
            stepIcon(ideExtensionInstalled ? "checkmark.circle.fill" : "terminal.fill",
                     color: ideExtensionInstalled ? .green : Constants.orangePrimary)

            VStack(spacing: 8) {
                Text("Switch terminals instantly")
                    .font(Constants.heading(size: 24, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)

                Text("Install a tiny extension so clicking a session in Masko jumps to the exact terminal tab.")
                    .font(Constants.body(size: 14))
                    .foregroundStyle(Constants.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            // Per-IDE detection list
            VStack(spacing: 6) {
                let detectedIDEs = ExtensionInstaller.availableIDEs()
                ForEach(detectedIDEs, id: \.command) { ide in
                    HStack(spacing: 8) {
                        Image(systemName: ideExtensionInstalled ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(ideExtensionInstalled ? .green : Constants.orangePrimary)
                            .font(.system(size: 10))
                        Text(ide.name)
                            .font(Constants.body(size: 14, weight: .medium))
                            .foregroundStyle(Constants.textPrimary)
                        Spacer()
                        Text("Detected")
                            .font(Constants.body(size: 12))
                            .foregroundStyle(Constants.textMuted)
                    }
                    .padding(.horizontal, 30)
                }
            }

            if let error = ideExtensionError {
                Text(error)
                    .font(Constants.body(size: 12))
                    .foregroundStyle(.red)
            }

            if ideExtensionInstalled {
                primaryButton("Continue") {
                    nextStep(after: 4)
                }
            } else {
                primaryButton("Install Extension") {
                    installIDEExtension()
                }

                skipButton { nextStep(after: 4) }
            }
        }
    }

    // MARK: - Step 5: Choose Mascot

    private var mascotStep: some View {
        VStack(spacing: 20) {
            stepIcon(mascotActivated ? "checkmark.circle.fill" : "wand.and.stars",
                     color: mascotActivated ? .green : Constants.orangePrimary)

            VStack(spacing: 8) {
                Text("Choose your mascot")
                    .font(Constants.heading(size: 24, weight: .bold))
                    .foregroundStyle(Constants.textPrimary)

                Text("Pick a companion that will live on your screen and react to Claude Code.")
                    .font(Constants.body(size: 14))
                    .foregroundStyle(Constants.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            // Preset grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 10)
            ], spacing: 10) {
                ForEach(MascotStore.presets) { preset in
                    PresetPickerCard(
                        preset: preset,
                        isSelected: selectedPresetSlug == preset.slug
                    ) {
                        selectedPresetSlug = preset.slug
                    }
                }
            }
            .padding(.horizontal, 20)

            if mascotActivated {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Mascot activated!")
                        .font(Constants.body(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                }

                primaryButton("Let's go!") {
                    onComplete()
                }
            } else {
                primaryButton(isLoadingPreset ? "Loading..." : "Activate Mascot") {
                    activateSelectedPreset()
                }
                .opacity(selectedPresetSlug == nil ? 0.5 : 1)
                .allowsHitTesting(selectedPresetSlug != nil && !isLoadingPreset)

                skipButton { onComplete() }
            }
        }
    }

    // MARK: - Shared Components

    private func stepIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 48))
            .foregroundStyle(color)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Constants.heading(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Constants.orangePrimary)
                .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                .shadow(color: Constants.orangeShadow, radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func skipButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Skip")
                .font(Constants.body(size: 13, weight: .medium))
                .foregroundStyle(Constants.textMuted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func enableHooks() {
        hookError = nil
        do {
            try HookInstaller.install()
            hookInstalled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                nextStep(after: 1)
            }
        } catch {
            hookError = error.localizedDescription
        }
    }

    private func installIDEExtension() {
        ideExtensionError = nil
        do {
            try ExtensionInstaller.install()
            ideExtensionInstalled = true
            UserDefaults.standard.set(true, forKey: "ideExtensionEnabled")
            ExtensionInstaller.triggerPermissionPrompt()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                nextStep(after: 4)
            }
        } catch {
            ideExtensionError = error.localizedDescription
        }
    }

    private func enableAccessibility() {
        appStore.hotkeyManager.requestAccessibilityPermission()
        // The system dialog is async — poll briefly for the result
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            accessibilityGranted = AXIsProcessTrusted()
            if accessibilityGranted {
                // Also start the hotkey manager now that we have permission
                appStore.hotkeyManager.start()
                nextStep(after: 3)
            }
        }
    }

    private func activateSelectedPreset() {
        guard let slug = selectedPresetSlug else { return }
        isLoadingPreset = true

        Task {
            await appStore.mascotStore.addPreset(slug: slug)

            await MainActor.run {
                isLoadingPreset = false
                if let mascot = appStore.mascotStore.mascots.first(where: { $0.templateSlug == slug }) {
                    overlayManager.showOverlayWithConfig(mascot.config)
                    mascotActivated = true
                }
            }
        }
    }
}

// MARK: - Preset Picker Card

struct PresetPickerCard: View {
    let preset: PresetInfo
    let isSelected: Bool
    let onTap: () -> Void

    private var presetConfig: MaskoAnimationConfig? {
        MascotStore.loadBundledConfig(named: preset.filename)
    }

    private var thumbnailURL: URL? {
        guard let config = presetConfig,
              let urlString = config.nodes.first?.transparentThumbnailUrl else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: Constants.cornerRadiusSmall)
                        .fill(Constants.stage)

                    if let url = thumbnailURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            default:
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                        .padding(8)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 24))
                            .foregroundStyle(Constants.orangePrimary.opacity(0.5))
                    }
                }
                .frame(height: 80)

                Text(presetConfig?.name ?? preset.slug)
                    .font(Constants.body(size: 12, weight: .medium))
                    .foregroundStyle(Constants.textPrimary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Constants.orangePrimary.opacity(0.08) : Constants.surfaceWhite)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .stroke(isSelected ? Constants.orangePrimary : Constants.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
