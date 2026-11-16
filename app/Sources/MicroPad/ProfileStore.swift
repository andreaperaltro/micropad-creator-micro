import Combine
import Foundation

/// Profiles saved in ~/Library/Application Support/MicroPad/profiles.json
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile]
    @Published var alerts: [AlertRule]
    @Published var globals: GlobalSlots
    private var saver: AnyCancellable?
    private var globalSaver: AnyCancellable?
    private var alertSaver: AnyCancellable?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MicroPad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    static var alertsURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("alerts.json")
    }

    static var globalsURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("globals.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.globalsURL),
           let loaded = try? JSONDecoder().decode(GlobalSlots.self, from: data) {
            globals = loaded
        } else {
            globals = GlobalSlots()
        }
        if let data = try? Data(contentsOf: Self.alertsURL),
           let loaded = try? JSONDecoder().decode([AlertRule].self, from: data) {
            alerts = loaded
        } else {
            alerts = AlertRule.defaults
        }
        if let data = try? Data(contentsOf: Self.fileURL),
           let loaded = try? JSONDecoder().decode([Profile].self, from: data),
           !loaded.isEmpty {
            profiles = loaded
        } else {
            profiles = DefaultProfiles.all()
        }
        if !profiles.contains(where: { $0.isBase }) {
            profiles.insert(DefaultProfiles.all()[0], at: 0)
        }
        saver = $profiles
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
        globalSaver = $globals
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
        alertSaver = $alerts
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
        save()
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(profiles) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
        if let data = try? enc.encode(globals) {
            try? data.write(to: Self.globalsURL, options: .atomic)
        }
        if let data = try? enc.encode(alerts) {
            try? data.write(to: Self.alertsURL, options: .atomic)
        }
    }

    var base: Profile { profiles.first(where: { $0.isBase }) ?? profiles[0] }
    var baseIndex: Int { profiles.firstIndex(where: { $0.isBase }) ?? 0 }

    /// The profile as the pad uses it: "All apps" keys and encoders come from the base profile.
    func effective(_ p: Profile) -> Profile {
        guard !p.isBase else { return p }
        var e = p
        let b = base
        for k in globals.keys where k >= 0 && k < e.keys.count { e.keys[k] = b.keys[k] }
        for x in globals.encoders where x >= 0 && x < e.encoders.count { e.encoders[x] = b.encoders[x] }
        return e
    }

    /// Make a key global, keeping the command it has in `profile`.
    func makeGlobal(key i: Int, from profile: Profile) {
        profiles[baseIndex].keys[i] = profile.keys[i]
        globals.keys.insert(i)
    }

    /// Make an encoder's rotation global, keeping the commands it has in `profile`.
    func makeGlobal(encoder e: Int, from profile: Profile) {
        profiles[baseIndex].encoders[e] = profile.encoders[e]
        globals.encoders.insert(e)
    }

    func profile(for bundleID: String?) -> Profile {
        guard let id = bundleID else { return base }
        return profiles.first(where: { $0.bundleIDs.contains(id) }) ?? base
    }

    func profile(id: UUID?) -> Profile? {
        profiles.first(where: { $0.id == id })
    }

    func resetToDefaults() {
        profiles = DefaultProfiles.all()
    }
}
