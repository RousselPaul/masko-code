import Foundation

struct SavedMascot: Identifiable, Codable {
    let id: UUID
    let name: String
    var config: MaskoAnimationConfig
    let addedAt: Date
    var templateSlug: String?
}

// MARK: - Preset Info

struct PresetInfo: Identifiable {
    let slug: String
    let filename: String // bundle resource name (no .json)
    let emoji: String

    var id: String { slug }
}

@Observable
final class MascotStore {
    private(set) var mascots: [SavedMascot] = []
    private static let filename = "mascots.json"

    private static let seedVersion = 4 // Bump to re-apply default config on next launch

    /// The 5 base mascot presets. Replace placeholder entries with real configs when ready.
    static let presets: [PresetInfo] = [
        PresetInfo(slug: "madame-patate", filename: "madame-patate", emoji: "🥔"),
        PresetInfo(slug: "otto", filename: "otto", emoji: "🐙"),
        PresetInfo(slug: "cupidon", filename: "cupidon", emoji: "💘"),
        PresetInfo(slug: "masko", filename: "masko", emoji: "⚡"),
        PresetInfo(slug: "rusty", filename: "rusty", emoji: "🤖"),
    ]

    /// Presets not yet added by the user.
    var availablePresets: [PresetInfo] {
        let addedSlugs = Set(mascots.compactMap(\.templateSlug))
        return Self.presets.filter { !addedSlugs.contains($0.slug) }
    }

    init() {
        mascots = LocalStorage.load([SavedMascot].self, from: Self.filename) ?? []
        if mascots.isEmpty {
            seedDefaults()
        } else {
            migrateSeedIfNeeded()
        }
    }

    private func seedDefaults() {
        // Seed the first preset for new users
        let firstPreset = Self.presets[0]
        Task {
            if let config = await Self.fetchRemoteConfig(slug: firstPreset.slug) {
                await MainActor.run {
                    self.addFromPreset(config: config, slug: firstPreset.slug)
                    UserDefaults.standard.set(Self.seedVersion, forKey: "defaultMascotSeedVersion")
                }
                return
            }
            // Offline fallback: load from bundle
            await MainActor.run {
                guard let config = Self.loadBundledConfig(named: firstPreset.filename) else { return }
                self.addFromPreset(config: config, slug: firstPreset.slug)
                UserDefaults.standard.set(Self.seedVersion, forKey: "defaultMascotSeedVersion")
            }
        }
    }

    static func fetchRemoteConfig(slug: String) async -> MaskoAnimationConfig? {
        guard let url = URL(string: "\(Constants.maskoBaseURL)/api/mascot-templates/\(slug)") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(MaskoAnimationConfig.self, from: data)
    }

    /// Re-apply bundled configs when the seed version is bumped (e.g. condition fixes).
    private func migrateSeedIfNeeded() {
        let current = UserDefaults.standard.integer(forKey: "defaultMascotSeedVersion")
        guard current < Self.seedVersion else { return }

        // Update any existing preset mascots with fresh bundled configs
        for preset in Self.presets {
            guard let config = Self.loadBundledConfig(named: preset.filename) else { continue }
            if let idx = mascots.firstIndex(where: { $0.templateSlug == preset.slug }) {
                mascots[idx].config = config
            }
        }
        persist()

        UserDefaults.standard.set(Self.seedVersion, forKey: "defaultMascotSeedVersion")
    }

    static func loadBundledConfig(named filename: String) -> MaskoAnimationConfig? {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json", subdirectory: "Defaults"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(MaskoAnimationConfig.self, from: data) else { return nil }
        return config
    }

    private func persist() {
        LocalStorage.save(mascots, to: Self.filename)
    }

    // MARK: - Preset Management

    /// Add a preset mascot by slug. Tries remote fetch first, falls back to bundled JSON.
    func addPreset(slug: String) async {
        // Already have this preset?
        guard !mascots.contains(where: { $0.templateSlug == slug }) else { return }

        // Try remote first
        if let config = await Self.fetchRemoteConfig(slug: slug) {
            await MainActor.run {
                addFromPreset(config: config, slug: slug)
            }
            return
        }

        // Fall back to bundled
        let filename = Self.presets.first(where: { $0.slug == slug })?.filename ?? slug
        await MainActor.run {
            guard let config = Self.loadBundledConfig(named: filename) else { return }
            addFromPreset(config: config, slug: slug)
        }
    }

    private func addFromPreset(config: MaskoAnimationConfig, slug: String) {
        let mascot = SavedMascot(
            id: UUID(),
            name: config.name,
            config: config,
            addedAt: Date(),
            templateSlug: slug
        )
        mascots.insert(mascot, at: 0)
        persist()
    }

    // MARK: - General Management

    func add(config: MaskoAnimationConfig) {
        let mascot = SavedMascot(
            id: UUID(),
            name: config.name,
            config: config,
            addedAt: Date(),
            templateSlug: nil
        )
        mascots.insert(mascot, at: 0)
        persist()
    }

    func remove(id: UUID) {
        mascots.removeAll { $0.id == id }
        persist()
    }

    func updateConfig(mascotId: UUID, config: MaskoAnimationConfig) {
        guard let idx = mascots.firstIndex(where: { $0.id == mascotId }) else { return }
        mascots[idx].config = config
        persist()
    }

    func updateEdgeConditions(mascotId: UUID, edgeId: String, conditions: [MaskoAnimationCondition]?) {
        guard let idx = mascots.firstIndex(where: { $0.id == mascotId }) else { return }
        guard let edgeIdx = mascots[idx].config.edges.firstIndex(where: { $0.id == edgeId }) else { return }
        mascots[idx].config.edges[edgeIdx].conditions = conditions
        persist()
    }
}
