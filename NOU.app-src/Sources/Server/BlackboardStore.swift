import Foundation

/// Shared knowledge store for agent-to-agent communication (like mesh-llm's Blackboard).
/// Agents on any node can read/write entries. Synced across paired nodes on refresh.
actor BlackboardStore {
    static let shared = BlackboardStore()
    private init() {}

    struct Entry: Codable, Sendable {
        var key: String
        var value: String
        var author: String       // "local" or remote node_id
        var timestamp: TimeInterval  // unix epoch
        var tags: [String]
        var ttl: TimeInterval?   // optional expiry (seconds from timestamp), nil = permanent
    }

    private var entries: [String: Entry] = [:]

    // MARK: - CRUD

    func set(key: String, value: String, author: String = "local",
             tags: [String] = [], ttl: TimeInterval? = nil) {
        entries[key] = Entry(
            key: key, value: value, author: author,
            timestamp: Date().timeIntervalSince1970,
            tags: tags, ttl: ttl
        )
        save()
    }

    func get(key: String) -> Entry? {
        guard let e = entries[key] else { return nil }
        if let ttl = e.ttl, Date().timeIntervalSince1970 > e.timestamp + ttl {
            entries.removeValue(forKey: key)
            save()
            return nil
        }
        return e
    }

    func delete(key: String) {
        entries.removeValue(forKey: key)
        save()
    }

    /// List all non-expired entries, optionally filtered by prefix or tag.
    func list(prefix: String? = nil, tag: String? = nil) -> [Entry] {
        let now = Date().timeIntervalSince1970
        return entries.values.filter { e in
            if let ttl = e.ttl, now > e.timestamp + ttl { return false }
            if let p = prefix, !e.key.hasPrefix(p) { return false }
            if let t = tag, !e.tags.contains(t) { return false }
            return true
        }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Export all entries as JSON-serializable array for sync/replication.
    func exportAll() -> [[String: Any]] {
        list().map { e in
            var d: [String: Any] = [
                "key": e.key, "value": e.value, "author": e.author,
                "timestamp": e.timestamp, "tags": e.tags
            ]
            if let ttl = e.ttl { d["ttl"] = ttl }
            return d
        }
    }

    /// Merge entries received from a remote node (remote wins if newer).
    func merge(remote: [[String: Any]]) {
        for d in remote {
            guard let key = d["key"] as? String,
                  let value = d["value"] as? String,
                  let ts = d["timestamp"] as? TimeInterval else { continue }
            let author = d["author"] as? String ?? "remote"
            let tags   = d["tags"] as? [String] ?? []
            let ttl    = d["ttl"] as? TimeInterval

            if let existing = entries[key], existing.timestamp >= ts { continue }
            entries[key] = Entry(key: key, value: value, author: author,
                                 timestamp: ts, tags: tags, ttl: ttl)
        }
        save()
    }

    // MARK: - Persistence (UserDefaults)

    private let udKey = "nou.blackboard.entries"

    private func save() {
        let raw = exportAll()
        UserDefaults.standard.set(raw, forKey: udKey)
    }

    private func load() {
        guard let raw = UserDefaults.standard.array(forKey: udKey) as? [[String: Any]] else { return }
        merge(remote: raw)
    }
}
