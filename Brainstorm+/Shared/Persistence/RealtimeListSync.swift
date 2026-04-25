import Foundation
import Supabase
import Realtime

// ══════════════════════════════════════════════════════════════════
// RealtimeListSync — Iter 8 P1 §B.9 helper
//
// Reusable wrapper around Supabase Realtime v2 `postgres_changes`
// subscription for list-style ViewModels. Hides the boilerplate of:
//   • channel naming (per-table + per-user keying)
//   • subscribing to INSERT/UPDATE/DELETE simultaneously via 3 streams
//   • teardown on view disappear
//
// Why a helper instead of inlining (chat-room style):
//   • TaskList / ApprovalCenter / Reporting / Announcements all want
//     the same shape — wire 3 actions, dispatch to a per-event
//     handler. Repeating the boilerplate in 4 VMs invites drift.
//   • Chat room is intentionally NOT migrated — it has filtered
//     channels, typing presence, and withdraw-aware reconciliation
//     that this helper deliberately doesn't model.
//
// Usage (iOS 17+):
//   private let realtime = RealtimeListSync(client: client, tableName: "tasks")
//   func subscribe() async {
//       await realtime.start { [weak self] change in
//           guard let self = self else { return }
//           switch change {
//           case .insert(let payload): self.applyInsert(payload)
//           case .update(let payload): self.applyUpdate(payload)
//           case .delete(let oldPayload): self.applyDelete(oldPayload)
//           }
//       }
//   }
//   func unsubscribe() async { await realtime.stop() }
// ══════════════════════════════════════════════════════════════════

/// Discriminated change event surfaced to the VM. Keeping the payload
/// as a JSONObject lets each VM decode into its own row type without
/// the helper having to be generic over Decodable.
public enum RealtimeListChange {
    case insert(JSONObject)
    case update(newRow: JSONObject, oldRow: JSONObject?)
    case delete(oldRow: JSONObject)
}

@MainActor
public final class RealtimeListSync {
    public let tableName: String
    private let schema: String
    private let client: SupabaseClient
    private let channelSuffix: String

    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    public init(
        client: SupabaseClient,
        tableName: String,
        schema: String = "public",
        channelSuffix: String = ""
    ) {
        self.client = client
        self.tableName = tableName
        self.schema = schema
        self.channelSuffix = channelSuffix
    }

    /// Returns true if a subscription is currently active. VMs use this
    /// to avoid double-subscribe when the view re-appears via tab swap.
    public var isActive: Bool { channel != nil }

    /// Subscribe to INSERT/UPDATE/DELETE for the configured table and
    /// fan-out into a single async stream of `RealtimeListChange`.
    /// Caller's handler runs on @MainActor.
    public func start(
        handler: @escaping @MainActor (RealtimeListChange) -> Void
    ) async {
        // Belt-and-suspenders: never double-subscribe.
        await stop()

        let suffix = channelSuffix.isEmpty
            ? UUID().uuidString.prefix(8).description
            : channelSuffix
        let name = "rt-\(tableName)-\(suffix)"
        let ch = client.channel(name)

        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: schema,
            table: tableName
        )
        let updates = ch.postgresChange(
            UpdateAction.self,
            schema: schema,
            table: tableName
        )
        let deletes = ch.postgresChange(
            DeleteAction.self,
            schema: schema,
            table: tableName
        )

        self.channel = ch

        do {
            try await ch.subscribeWithError()
        } catch {
            // Soft-fail — subscription internals will retry the WebSocket;
            // we still wire the stream tasks so reconnects deliver events.
        }

        self.task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await change in inserts {
                        guard self != nil else { return }
                        await MainActor.run {
                            handler(.insert(change.record))
                        }
                    }
                }
                group.addTask {
                    for await change in updates {
                        guard self != nil else { return }
                        await MainActor.run {
                            handler(.update(newRow: change.record, oldRow: change.oldRecord))
                        }
                    }
                }
                group.addTask {
                    for await change in deletes {
                        guard self != nil else { return }
                        await MainActor.run {
                            handler(.delete(oldRow: change.oldRecord))
                        }
                    }
                }
            }
        }
    }

    /// Cancel the fan-out task and remove the underlying realtime channel.
    /// Idempotent; safe to call from `.onDisappear` and `deinit` style.
    public func stop() async {
        task?.cancel()
        task = nil
        if let ch = channel {
            await client.removeChannel(ch)
            channel = nil
        }
    }
}

// MARK: - JSONObject decode helpers

public extension JSONObject {
    /// Convenience: decode the realtime payload into the VM's model.
    /// Returns nil on decode failure (e.g. missing fields after a
    /// schema migration); callers usually want to fall through and
    /// trigger a re-fetch rather than crash.
    func tryDecode<T: Decodable>(as type: T.Type) -> T? {
        try? self.decode(as: type)
    }

    /// Pull a single UUID column out of a delete payload (postgres_changes
    /// only includes primary-key columns in `oldRecord` by default).
    func uuidColumn(_ key: String) -> UUID? {
        guard let raw = self[key] else { return nil }
        switch raw {
        case .string(let s): return UUID(uuidString: s)
        default: return nil
        }
    }
}
