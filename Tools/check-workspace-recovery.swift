import Foundation

@main enum RecoveryChecks {
    struct Job: Codable, Equatable {
        var photos: [String]
        var current: String?
        var quality: Int
        var failEncoding = false
        func encode(to encoder: Encoder) throws {
            if failEncoding { throw NSError(domain: "deliberate-encoding-failure", code: 1) }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(photos, forKey: .photos); try c.encodeIfPresent(current, forKey: .current)
            try c.encode(quality, forKey: .quality); try c.encode(false, forKey: .failEncoding)
        }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grainagent-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "current.json")
        let file = RecoveryFile<Job>(url: path)
        let first = Job(photos: ["b", "a"], current: "a", quality: 83)
        let next = Job(photos: ["b", "a", "c"], current: "c", quality: 91)
        precondition(file.load().value == nil)
        try file.save(first)
        precondition(RecoveryFile<Job>(url: path).load().value == first, "A new process must restore order, selection and recipe")
        try file.save(next)
        var failing = next; failing.failEncoding = true
        do { try file.save(failing); fatalError("Encoding failure must be reported") } catch {}
        precondition(RecoveryFile<Job>(url: path).load().value == next, "Failed save must keep the previous job")
        try Data("broken".utf8).write(to: path)
        let repaired = RecoveryFile<Job>(url: path)
        let backup = repaired.load()
        precondition(backup.usedBackup && backup.value == first, "A broken current file must recover its last valid backup")
        try repaired.save(next)
        let keptBackup = try Data(contentsOf: file.backupURL)
        precondition(keptBackup != Data("broken".utf8))
        precondition(RecoveryFile<Job>(url: path).load().value == next)
        let empty = Job(photos: [], current: nil, quality: 95)
        try repaired.save(empty)
        precondition(RecoveryFile<Job>(url: path).load().value == empty, "An intentionally emptied batch must stay empty")
        let future = Data("{\"version\":999,\"value\":{}}".utf8)
        try future.write(to: path)
        let blocked = RecoveryFile<Job>(url: path)
        precondition(blocked.load().problem != nil)
        do { try blocked.save(empty); fatalError("Newer checkpoints must not be overwritten") } catch {}
        let keptFuture = try Data(contentsOf: path)
        precondition(keptFuture == future)
        print("PASS: restart round-trip, ordering/selection, failed-save preservation, backup recovery, explicit empty batch, newer-version protection")
    }
}
