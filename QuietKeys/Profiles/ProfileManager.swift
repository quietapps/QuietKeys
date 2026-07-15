import Foundation

/// A switch profile: one folder of samples described by a manifest.json.
/// Adding a new profile is drop-in — new folder + manifest, no code changes.
struct Profile: Identifiable, Hashable {
    struct KeyEntry: Codable, Hashable {
        let down: [String]
        let up: [String]
    }

    let id: String
    let name: String
    let brand: String
    let type: String
    let gain: Float
    let keys: [String: KeyEntry]
    let directory: URL

    private struct Manifest: Codable {
        let id: String
        let name: String
        let brand: String
        let type: String
        let gain: Float?
        let keys: [String: KeyEntry]
    }

    init?(directory: URL) {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        id = m.id
        name = m.name
        brand = m.brand
        type = m.type
        gain = m.gain ?? 1.0
        keys = m.keys
        self.directory = directory
    }
}

/// The shared mouse-click sample set (profile-independent).
struct MouseManifest {
    let buttons: [MouseButton: Profile.KeyEntry]
    let directory: URL

    private struct Manifest: Codable {
        let buttons: [String: Profile.KeyEntry]
    }

    init?(directory: URL) {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        var mapped: [MouseButton: Profile.KeyEntry] = [:]
        for (key, entry) in m.buttons {
            if let button = MouseButton(rawValue: key) { mapped[button] = entry }
        }
        buttons = mapped
        self.directory = directory
    }
}

/// Discovers profiles in the app bundle and in the user's Application Support
/// directory (`~/Library/Application Support/Quiet Keys/Profiles`), so users
/// can add their own sample sets without rebuilding the app.
final class ProfileManager {
    private(set) var profiles: [Profile] = []
    private(set) var mouseManifest: MouseManifest?

    var brands: [String] {
        var seen = Set<String>()
        return profiles.map(\.brand).filter { seen.insert($0).inserted }
    }

    func profiles(for brand: String) -> [Profile] {
        profiles.filter { $0.brand == brand }
    }

    func profile(id: String) -> Profile? {
        profiles.first { $0.id == id }
    }

    init() {
        reload()
    }

    func reload() {
        var found: [Profile] = []
        for root in searchRoots() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)
            else { continue }
            for dir in entries {
                if dir.lastPathComponent == "_mouse" {
                    if mouseManifest == nil {
                        mouseManifest = MouseManifest(directory: dir)
                    }
                    continue
                }
                if let profile = Profile(directory: dir),
                   !found.contains(where: { $0.id == profile.id }) {
                    found.append(profile)
                }
            }
        }
        profiles = found.sorted { ($0.brand, $0.name) < ($1.brand, $1.name) }
    }

    private func searchRoots() -> [URL] {
        var roots: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Profiles") {
            roots.append(bundled)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("Quiet Keys/Profiles"))
        }
        return roots
    }
}
