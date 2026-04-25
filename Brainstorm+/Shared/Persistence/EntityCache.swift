import Foundation

// ══════════════════════════════════════════════════════════════════
// EntityCache — Iter 6 review §B.4 cache layer
//
// Two-tier cache (memory + disk) for high-traffic list view models so
// the UI can render instantly with stale data while the network fetch
// happens in the background. Disk records carry a TTL header so we can
// purge expired entries on app launch.
//
// Architecture:
//   • Memory: NSCache<NSString, AnyObject> wrapped through an
//     `Entry` reference type. Auto-evicts on memory pressure.
//   • Disk:   ~/Library/Caches/bs-cache/<base64(key)>.json
//             { "createdAt": "2026-04-25T...", "ttl": 86400, "value": <T> }
//
// Why iso8601 + JSONSerialization roundtrip rather than a sqlite blob:
// our cached payloads are already Codable, JSON keeps them inspectable
// for debugging, and the keys are bounded by the number of high-traffic
// VMs (≤ 6 today). NSCache costLimit isn't set — we rely on the OS
// memory-pressure callback for eviction.
//
// Thread-safety: confined to the main actor because callers are VMs
// that already run on @MainActor.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class EntityCache {

    public static let shared = EntityCache()

    // MARK: - Internals

    /// NSCache only stores AnyObject — wrap value-type payloads in a
    /// boxed reference so Swift structs (e.g. [TaskModel]) can sit in
    /// the memory tier without conforming to NSCoding.
    private final class Entry {
        let data: Data
        let createdAt: Date
        let ttl: TimeInterval

        init(data: Data, createdAt: Date, ttl: TimeInterval) {
            self.data = data
            self.createdAt = createdAt
            self.ttl = ttl
        }

        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > ttl
        }
    }

    private let memoryCache = NSCache<NSString, Entry>()
    private let diskCacheDir: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("bs-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskCacheDir = dir
    }

    // MARK: - Disk record

    private struct DiskRecord<T: Codable>: Codable {
        let createdAt: Date
        let ttl: TimeInterval
        let value: T
    }

    private struct DiskHeader: Codable {
        let createdAt: Date
        let ttl: TimeInterval
    }

    // MARK: - Path helpers

    /// Maps an arbitrary cache key to a deterministic, filesystem-safe
    /// filename. base64 keeps it readable enough during debugging while
    /// avoiding "/" or ":" in keys.
    private func diskURL(for key: String) -> URL {
        let encoded = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return diskCacheDir.appendingPathComponent("\(encoded).json")
    }

    // MARK: - Public API

    /// Write a value to both memory and disk. `ttl` defaults to 24 hours
    /// — long enough for stale-while-revalidate to keep the UI from
    /// showing blank when offline for a day, short enough that genuinely
    /// stale data eventually disappears.
    public func store<T: Codable>(_ value: T, key: String, ttl: TimeInterval = 86_400) async {
        let now = Date()
        do {
            let record = DiskRecord(createdAt: now, ttl: ttl, value: value)
            let payload = try encoder.encode(record)
            // Encode the *value* once for the memory tier so reads avoid
            // a re-encode (the disk record holds the same bytes inside).
            let valueData = try encoder.encode(value)

            let entry = Entry(data: valueData, createdAt: now, ttl: ttl)
            memoryCache.setObject(entry, forKey: key as NSString)

            // Disk write off the main actor — blocks of any size shouldn't
            // pause the UI. We don't propagate the error: cache failures
            // are best-effort.
            let url = diskURL(for: key)
            await Task.detached(priority: .utility) {
                try? payload.write(to: url, options: [.atomic])
            }.value
        } catch {
            #if DEBUG
            print("[EntityCache] store(\(key)) encode failed: \(error)")
            #endif
        }
    }

    /// Read from memory first (synchronous), fall through to disk. Returns
    /// `nil` for missing OR expired entries. Expired disk records are
    /// removed lazily on read so the next launch sees a clean directory.
    public func fetch<T: Codable>(_ type: T.Type, key: String) async -> T? {
        // ── Memory tier ────────────────────────────────────────────
        if let entry = memoryCache.object(forKey: key as NSString) {
            if entry.isExpired {
                memoryCache.removeObject(forKey: key as NSString)
            } else {
                if let decoded = try? decoder.decode(T.self, from: entry.data) {
                    return decoded
                }
            }
        }

        // ── Disk tier ──────────────────────────────────────────────
        let url = diskURL(for: key)
        let data: Data? = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
        guard let data else { return nil }

        do {
            let record = try decoder.decode(DiskRecord<T>.self, from: data)
            if Date().timeIntervalSince(record.createdAt) > record.ttl {
                // Expired — remove and treat as miss.
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            // Re-warm the memory tier so the next read in this session
            // skips the disk hit. Encode just the value so the entry
            // mirrors what `store` writes.
            if let valueData = try? encoder.encode(record.value) {
                memoryCache.setObject(
                    Entry(data: valueData, createdAt: record.createdAt, ttl: record.ttl),
                    forKey: key as NSString
                )
            }
            return record.value
        } catch {
            #if DEBUG
            print("[EntityCache] fetch(\(key)) decode failed: \(error)")
            #endif
            // Stale schema — drop the row so it doesn't keep failing.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Drop a single entry from both tiers. Used after destructive
    /// mutations where the cached snapshot is known-stale (e.g. on
    /// logout, or after a bulk import).
    public func purge(key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let url = diskURL(for: key)
        try? FileManager.default.removeItem(at: url)
    }

    /// Walk the disk directory and remove every record whose TTL has
    /// elapsed. Call from app launch — the result is best-effort.
    public func purgeExpired() async {
        let dir = self.diskCacheDir
        let dec = self.decoder
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return }
            let now = Date()
            for url in entries where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let header = try? dec.decode(DiskHeader.self, from: data) else { continue }
                if now.timeIntervalSince(header.createdAt) > header.ttl {
                    try? fm.removeItem(at: url)
                }
            }
        }.value
    }

    /// Fully empty both tiers. Reserved for "logout" / "clear caches"
    /// settings entry; not used on the hot path.
    public func purgeAll() {
        memoryCache.removeAllObjects()
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir,
            includingPropertiesForKeys: nil
        ) {
            for url in entries { try? FileManager.default.removeItem(at: url) }
        }
    }
}

// MARK: - Convenience keys
//
// Centralised cache keys to keep VMs from drifting on string spelling
// and to make it grep-able when we want to invalidate a tier.
public enum EntityCacheKey {
    public static func tasks(userId: UUID?) -> String {
        "tasks::\(userId?.uuidString ?? "anon")"
    }
    public static func chatChannels(userId: UUID?) -> String {
        "chat.channels::\(userId?.uuidString ?? "anon")"
    }
    public static func notifications(userId: UUID?) -> String {
        "notifications::\(userId?.uuidString ?? "anon")"
    }
    public static func activityFeed(userId: UUID?) -> String {
        "activity.feed::\(userId?.uuidString ?? "anon")"
    }
    public static func reportingDaily(userId: UUID?) -> String {
        "reporting.daily::\(userId?.uuidString ?? "anon")"
    }
    public static func reportingWeekly(userId: UUID?) -> String {
        "reporting.weekly::\(userId?.uuidString ?? "anon")"
    }
    public static func approvalsMine(userId: UUID?) -> String {
        "approvals.mine::\(userId?.uuidString ?? "anon")"
    }
    public static func approvalsQueue(userId: UUID?, kindRaw: String) -> String {
        "approvals.queue::\(userId?.uuidString ?? "anon")::\(kindRaw)"
    }
}
