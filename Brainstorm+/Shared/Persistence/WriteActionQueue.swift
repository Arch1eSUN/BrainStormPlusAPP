import Foundation

// ══════════════════════════════════════════════════════════════════
// WriteActionQueue — Iter 6 review §B.4 retry queue
//
// Persists pending write actions to disk so a network failure /
// app-kill / crash doesn't drop user mutations on the floor. When the
// network is reachable again (NetworkMonitor flips offline → online)
// or the app launches with a non-empty queue, we drain it through
// registered handlers.
//
// File path: ~/Library/Application Support/bs-queue/queue.json
// (Application Support is preserved across launches, unlike Caches.)
//
// Retry policy:
//   • 4xx → drop (server-side validation failure, replaying won't help)
//   • 5xx / network error → bump retryCount, re-enqueue with backoff
//   • >= maxRetries → drop with a log
//
// Backoff is exponential with jitter: base 2s, cap 60s. We don't sleep
// between actions during a single drain — drains finish as quickly as
// possible; the backoff applies to "when does the next retry attempt
// run after a failed dequeue". Per-action attempt is governed by
// `nextEligibleAt`.
// ══════════════════════════════════════════════════════════════════

public actor WriteActionQueue {

    public static let shared = WriteActionQueue()

    // MARK: - Action

    public struct Action: Codable, Identifiable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let kind: String
        public let payloadJSON: Data
        public var retryCount: Int
        public var nextEligibleAt: Date

        public init(
            id: UUID = UUID(),
            createdAt: Date = Date(),
            kind: String,
            payloadJSON: Data,
            retryCount: Int = 0,
            nextEligibleAt: Date = Date()
        ) {
            self.id = id
            self.createdAt = createdAt
            self.kind = kind
            self.payloadJSON = payloadJSON
            self.retryCount = retryCount
            self.nextEligibleAt = nextEligibleAt
        }
    }

    /// Outcome returned by a handler so the queue knows whether to
    /// drop, retry, or treat as success.
    public enum HandlerOutcome: Sendable {
        case success
        /// Permanent failure — drop the action. Use for 4xx, validation
        /// errors, schema mismatch.
        case dropPermanent(reason: String)
        /// Transient failure — bump retry count, re-enqueue with backoff.
        case retry(reason: String)
    }

    public typealias Handler = @Sendable (_ payloadJSON: Data) async -> HandlerOutcome

    // MARK: - Internals

    private let maxRetries = 5
    private let backoffBaseSeconds: Double = 2
    private let backoffCapSeconds: Double = 60

    private var actions: [Action] = []
    private var handlers: [String: Handler] = [:]
    private var didLoadFromDisk = false
    private var isProcessing = false

    private var queueFileURL: URL {
        let supportDir = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = supportDir.appendingPathComponent("bs-queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue.json")
    }

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

    private init() {}

    // MARK: - Disk persistence

    private func loadFromDiskIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let data = try? Data(contentsOf: queueFileURL),
              let loaded = try? decoder.decode([Action].self, from: data) else { return }
        actions = loaded
        #if DEBUG
        print("[WriteActionQueue] loaded \(loaded.count) action(s) from disk")
        #endif
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(actions)
            try data.write(to: queueFileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("[WriteActionQueue] save failed: \(error)")
            #endif
        }
    }

    // MARK: - Public API

    /// Register a handler for a `kind`. Handlers must be idempotent —
    /// the queue may invoke them more than once if the network drops
    /// between an apparent success and the queue's removal write.
    public func registerHandler(kind: String, _ handler: @escaping Handler) {
        handlers[kind] = handler
    }

    /// Enqueue a pending action and persist immediately. Triggers a
    /// best-effort drain in case we're already online — typical entry
    /// point is a write call that just hit a network error.
    public func enqueue(_ action: Action) async {
        loadFromDiskIfNeeded()
        actions.append(action)
        saveToDisk()
        #if DEBUG
        print("[WriteActionQueue] enqueued \(action.kind) id=\(action.id)")
        #endif
    }

    /// Convenience: encode any Codable payload + enqueue under `kind`.
    public func enqueue<T: Codable>(kind: String, payload: T) async {
        do {
            let data = try encoder.encode(payload)
            await enqueue(Action(kind: kind, payloadJSON: data))
        } catch {
            #if DEBUG
            print("[WriteActionQueue] enqueue<\(kind)> encode failed: \(error)")
            #endif
        }
    }

    public func pendingCount() async -> Int {
        loadFromDiskIfNeeded()
        return actions.count
    }

    public func snapshot() async -> [Action] {
        loadFromDiskIfNeeded()
        return actions
    }

    /// Drain eligible actions through their handlers. Called by
    /// NetworkMonitor on the offline → online transition and at app
    /// launch. Re-entrant safe — concurrent calls collapse into one.
    public func processQueue() async {
        loadFromDiskIfNeeded()
        guard !isProcessing else { return }
        guard !actions.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let now = Date()
        // Snapshot the eligible ids; we mutate `actions` as we go.
        let eligibleIds = actions
            .filter { $0.nextEligibleAt <= now }
            .map { $0.id }

        for id in eligibleIds {
            guard let action = actions.first(where: { $0.id == id }) else { continue }
            guard let handler = handlers[action.kind] else {
                #if DEBUG
                print("[WriteActionQueue] no handler for kind=\(action.kind), keeping in queue")
                #endif
                continue
            }

            let outcome = await handler(action.payloadJSON)
            switch outcome {
            case .success:
                actions.removeAll { $0.id == id }

            case .dropPermanent(let reason):
                #if DEBUG
                print("[WriteActionQueue] drop \(action.kind) id=\(id): \(reason)")
                #endif
                actions.removeAll { $0.id == id }

            case .retry(let reason):
                if action.retryCount + 1 >= maxRetries {
                    #if DEBUG
                    print("[WriteActionQueue] giving up \(action.kind) id=\(id) after \(action.retryCount + 1) tries: \(reason)")
                    #endif
                    actions.removeAll { $0.id == id }
                } else {
                    let delay = min(
                        backoffCapSeconds,
                        backoffBaseSeconds * pow(2, Double(action.retryCount))
                    )
                    let jitter = Double.random(in: 0...(delay * 0.25))
                    let next = Date().addingTimeInterval(delay + jitter)
                    if let idx = actions.firstIndex(where: { $0.id == id }) {
                        var bumped = actions[idx]
                        bumped.retryCount += 1
                        bumped.nextEligibleAt = next
                        actions[idx] = bumped
                    }
                    #if DEBUG
                    print("[WriteActionQueue] retry \(action.kind) id=\(id) in \(Int(delay))s (try \(action.retryCount + 1)/\(maxRetries)): \(reason)")
                    #endif
                }
            }
        }

        saveToDisk()
    }

    /// Diagnostics + settings entry: drop everything. Caller is
    /// responsible for warning the user that pending writes will be
    /// lost.
    public func clearAll() async {
        actions.removeAll()
        saveToDisk()
    }
}

// MARK: - Action kinds
//
// Centralised so callers and handler registrations agree on spelling.
public enum WriteActionKind {
    public static let taskCreate = "task.create"
    public static let taskUpdate = "task.update"
    public static let approvalAction = "approval.action"
    public static let chatSendMessage = "chat.send_message"
}
