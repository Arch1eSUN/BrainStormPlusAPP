import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// WriteActionHandlers — Iter 6 review §B.4 handler registry
//
// Concrete replay handlers for each `WriteActionKind`. Registered once
// at app launch (BrainStormApp.init); the queue invokes them when the
// network comes back online and there is something to drain.
//
// Why not put handlers next to the VMs that originate the actions:
//   • The queue lives outside the VM lifecycle — VMs come and go as
//     tabs swap, but a queued action must survive that. The handler
//     therefore can't capture VM state; it has to talk straight to
//     Supabase.
//   • Centralising them makes it obvious which kinds are wired and
//     keeps the encode/decode contract for `payloadJSON` documented in
//     a single file (the matching encode site lives in the VM).
//
// Error classification:
//   • PostgrestError with status 4xx → `.dropPermanent` (validation,
//     RLS denial, unique violation — replaying won't help)
//   • Anything else (network, 5xx, decode) → `.retry`
// ══════════════════════════════════════════════════════════════════

public enum WriteActionHandlers {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func registerAll() async {
        let client = supabase

        await WriteActionQueue.shared.registerHandler(kind: WriteActionKind.taskCreate) { payload in
            await handleTaskCreate(payload, client: client)
        }
        await WriteActionQueue.shared.registerHandler(kind: WriteActionKind.taskUpdate) { payload in
            await handleTaskUpdate(payload, client: client)
        }
        await WriteActionQueue.shared.registerHandler(kind: WriteActionKind.approvalAction) { payload in
            await handleApprovalAction(payload, client: client)
        }
        await WriteActionQueue.shared.registerHandler(kind: WriteActionKind.chatSendMessage) { payload in
            await handleChatSendMessage(payload, client: client)
        }
    }

    // MARK: - Payload contracts (match what the VMs encode)

    /// task.create — minimal task insert. We don't replay the
    /// participants insert here because participant rows are
    /// best-effort even online; the RLS trigger auto-adds owner.
    public struct TaskCreatePayload: Codable, Sendable {
        public let title: String
        public let description: String?
        public let priority: String
        public let status: String
        public let due_date: String?
        public let project_id: UUID?
        public let owner_id: UUID
        public let reporter_id: UUID
        public let created_by: UUID
        public let assignee_id: UUID
        public let progress: Int

        public init(
            title: String,
            description: String?,
            priority: String,
            status: String,
            due_date: String?,
            project_id: UUID?,
            owner_id: UUID,
            reporter_id: UUID,
            created_by: UUID,
            assignee_id: UUID,
            progress: Int
        ) {
            self.title = title
            self.description = description
            self.priority = priority
            self.status = status
            self.due_date = due_date
            self.project_id = project_id
            self.owner_id = owner_id
            self.reporter_id = reporter_id
            self.created_by = created_by
            self.assignee_id = assignee_id
            self.progress = progress
        }
    }

    public struct TaskStatusUpdatePayload: Codable, Sendable {
        public let task_id: UUID
        public let new_status: String
        public init(task_id: UUID, new_status: String) {
            self.task_id = task_id
            self.new_status = new_status
        }
    }

    public struct ApprovalActionPayload: Codable, Sendable {
        public let request_id: UUID
        public let decision: String
        public let comment: String?
        public init(request_id: UUID, decision: String, comment: String?) {
            self.request_id = request_id
            self.decision = decision
            self.comment = comment
        }
    }

    public struct ChatSendMessagePayload: Codable, Sendable {
        public let channel_id: UUID
        public let sender_id: UUID
        public let content: String
        public let type: String
        public let attachments: [ChatAttachment]
        public let reply_to: UUID?
        public init(
            channel_id: UUID,
            sender_id: UUID,
            content: String,
            type: String,
            attachments: [ChatAttachment],
            reply_to: UUID?
        ) {
            self.channel_id = channel_id
            self.sender_id = sender_id
            self.content = content
            self.type = type
            self.attachments = attachments
            self.reply_to = reply_to
        }
    }

    // MARK: - Handlers

    private static func handleTaskCreate(
        _ payload: Data,
        client: SupabaseClient
    ) async -> WriteActionQueue.HandlerOutcome {
        do {
            let decoded = try decoder.decode(TaskCreatePayload.self, from: payload)
            try await client.from("tasks").insert(decoded).execute()
            return .success
        } catch {
            return classify(error)
        }
    }

    private static func handleTaskUpdate(
        _ payload: Data,
        client: SupabaseClient
    ) async -> WriteActionQueue.HandlerOutcome {
        do {
            let decoded = try decoder.decode(TaskStatusUpdatePayload.self, from: payload)
            try await client
                .from("tasks")
                .update(["status": decoded.new_status])
                .eq("id", value: decoded.task_id)
                .execute()
            return .success
        } catch {
            return classify(error)
        }
    }

    private static func handleApprovalAction(
        _ payload: Data,
        client: SupabaseClient
    ) async -> WriteActionQueue.HandlerOutcome {
        do {
            let decoded = try decoder.decode(ApprovalActionPayload.self, from: payload)
            struct RPCParams: Encodable {
                let p_request_id: String
                let p_decision: String
                let p_comment: String?
            }
            let _: UUID = try await client
                .rpc(
                    "approvals_apply_action",
                    params: RPCParams(
                        p_request_id: decoded.request_id.uuidString,
                        p_decision: decoded.decision,
                        p_comment: decoded.comment
                    )
                )
                .execute()
                .value
            return .success
        } catch {
            return classify(error)
        }
    }

    private static func handleChatSendMessage(
        _ payload: Data,
        client: SupabaseClient
    ) async -> WriteActionQueue.HandlerOutcome {
        do {
            let decoded = try decoder.decode(ChatSendMessagePayload.self, from: payload)
            struct InsertPayload: Encodable {
                let channel_id: String
                let sender_id: String
                let content: String
                let type: String
                let attachments: [ChatAttachment]
                let reply_to: String?
            }
            try await client
                .from("chat_messages")
                .insert(InsertPayload(
                    channel_id: decoded.channel_id.uuidString,
                    sender_id: decoded.sender_id.uuidString,
                    content: decoded.content,
                    type: decoded.type,
                    attachments: decoded.attachments,
                    reply_to: decoded.reply_to?.uuidString
                ))
                .execute()
            return .success
        } catch {
            return classify(error)
        }
    }

    // MARK: - Error classification

    /// Turn an arbitrary error into a queue outcome. We err on the side
    /// of `.retry` — when in doubt the user prefers eventual delivery
    /// over silent loss.
    private static func classify(_ error: Error) -> WriteActionQueue.HandlerOutcome {
        let message = error.localizedDescription
        let lower = message.lowercased()

        // 4xx-ish heuristics — Supabase Swift surfaces these as
        // PostgrestError but we keep the check string-based to avoid a
        // hard dependency on the concrete type.
        let permanentMarkers = [
            "duplicate key", "unique constraint",
            "violates foreign key", "violates check constraint",
            "row-level security", "permission denied",
            "invalid input", "23505", "42501"
        ]
        if permanentMarkers.contains(where: { lower.contains($0) }) {
            return .dropPermanent(reason: message)
        }

        return .retry(reason: message)
    }
}
