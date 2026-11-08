import Foundation

/// Product identity is independent of the unchanged spektrafilm engine ABI,
/// profile IDs, sidecar schema and resource names.
enum AppIdentity {
    static let name = "GrainAgent"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.richardcaroljy.GrainAgent"
    static let maintainer = Bundle.main.object(forInfoDictionaryKey: "GrainAgentMaintainer") as? String ?? "Richard Jin"
    static let repository = Bundle.main.object(forInfoDictionaryKey: "GrainAgentRepository") as? String ?? "https://github.com/RichardCarolJ/GrainAgent"
    static let command = "grainagent"
    static let logPrefix = "grainagent-"
    static let releaseTagPrefix = Bundle.main.object(forInfoDictionaryKey: "GrainAgentReleaseTagPrefix") as? String ?? "v"
    static var publicReleaseChannel: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "GrainAgentPublicReleaseChannel")
        return (value as? Bool) ?? ((value as? NSString)?.boolValue ?? false)
    }
    static var latestReleaseURL: URL? {
        guard publicReleaseChannel, let repositoryURL = URL(string: repository) else { return nil }
        return URL(string: "https://api.github.com/repos\(repositoryURL.path)/releases/latest")
    }

    /// Copy development preferences before any Session or observable settings
    /// are constructed. Never replace a value already set in the release app;
    /// the existing GrainAgent workspace and sidecar directories stay in place.
    static func migrateDevelopmentPreferences(defaults: UserDefaults = .standard,
        destination: String = bundleIdentifier, legacy: String = "local.grainagent.development") {
        guard destination != legacy else { return }
        let marker = "grainagent.releasePreferencesMigrated.v1"
        var current = defaults.persistentDomain(forName: destination) ?? [:]
        guard current[marker] as? Bool != true else { return }
        for (key, value) in defaults.persistentDomain(forName: legacy) ?? [:] where current[key] == nil {
            current[key] = value
        }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: destination)
        defaults.synchronize()
    }
    // An independent app must not adopt/delete another app's neighbouring files.
    // Existing edits can later be imported explicitly without changing the schema.
    static let importsLegacySidecars = false
}
