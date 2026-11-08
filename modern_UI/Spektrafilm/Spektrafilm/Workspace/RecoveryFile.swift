import Foundation

/// One atomic checkpoint plus the preceding valid checkpoint. A damaged or
/// newer-version file is never silently replaced by an empty launch session.
final class RecoveryFile<Value: Codable> {
    struct Envelope: Codable { var version = 1; var value: Value }
    private struct Header: Decodable { let version: Int }
    struct Loaded { var value: Value?; var usedBackup = false; var problem: String? }
    enum Failure: LocalizedError {
        case newerVersion, unreadable
        var errorDescription: String? {
            switch self {
            case .newerVersion: "上次工作由较新版本保存，请使用较新版本打开。"
            case .unreadable: "无法读取上次工作记录；原记录已保留。"
            }
        }
    }
    let url: URL
    var backupURL: URL { url.deletingPathExtension().appendingPathExtension("previous.json") }
    private var blocked = false
    init(url: URL) { self.url = url }
    private func decode(_ data: Data) throws -> Value {
        guard try JSONDecoder().decode(Header.self, from: data).version == 1 else { throw Failure.newerVersion }
        return try JSONDecoder().decode(Envelope.self, from: data).value
    }
    func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(value: nil) }
        do { return Loaded(value: try decode(Data(contentsOf: url))) }
        catch Failure.newerVersion { blocked = true; return Loaded(value: nil, problem: Failure.newerVersion.localizedDescription) }
        catch {
            if let data = try? Data(contentsOf: backupURL), let value = try? decode(data) {
                return Loaded(value: value, usedBackup: true)
            }
            blocked = true
            return Loaded(value: nil, problem: Failure.unreadable.localizedDescription)
        }
    }
    func save(_ value: Value) throws {
        guard !blocked else { throw Failure.unreadable }
        let data = try JSONEncoder().encode(Envelope(value: value))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: url) {
            if (try? decode(previous)) != nil { try previous.write(to: backupURL, options: .atomic) }
            else {
                // Keep the broken original for recovery; do not replace the good backup.
                let retained = url.deletingLastPathComponent().appendingPathComponent("damaged-\(UUID().uuidString).json")
                try previous.write(to: retained, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
