import Combine
import Foundation

/// Profiles saved in ~/Library/Application Support/MicroPad/profiles.json
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile]
    @Published var alerts: [AlertRule]
    private var saver: AnyCancellable?
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

    init() {
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
        if let data = try? enc.encode(alerts) {
            try? data.write(to: Self.alertsURL, options: .atomic)
        }
    }

    var base: Profile { profiles.first(where: { $0.isBase }) ?? profiles[0] }

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
