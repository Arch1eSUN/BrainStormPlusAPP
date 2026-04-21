import Foundation
import Combine
import Supabase

@MainActor
public class ChatRoomViewModel: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    @Published public var isLoading: Bool = false
    @Published public var isSending: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var accessDenied: Bool = false
    @Published public var currentUserId: UUID? = nil

    private let client: SupabaseClient
    public let channel: ChatChannel

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    public init(client: SupabaseClient, channel: ChatChannel) {
        self.client = client
        self.channel = channel
    }

    /// Mirrors Web `ensureChannelAccess` (src/lib/actions/chat.ts:284-305):
    /// announcement OR created_by OR membership. MUST gate BEFORE any
    /// fetch/subscribe so a deep-link into an inaccessible channel reveals
    /// nothing.
    public func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
            currentUserId = userId
        } catch {
            accessDenied = true
            return
        }

        if channel.type == .announcement || channel.createdBy == userId {
            await fetchMessages()
            await subscribeRealtime()
            return
        }

        do {
            let rows: [ChatChannelMember] = try await client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at")
                .eq("channel_id", value: channel.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            if rows.isEmpty {
                accessDenied = true
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            accessDenied = true
            return
        }

        await fetchMessages()
        await subscribeRealtime()
    }

    /// Matches Web `fetchMessages` (src/lib/actions/chat.ts:539-576):
    /// ORDER BY created_at ASC LIMIT 50. We intentionally skip the reply_to
    /// second-query here — reply rendering is 3.2+ scope.
    public func fetchMessages() async {
        do {
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("channel_id", value: channel.id.uuidString)
                .order("created_at", ascending: true)
                .limit(50)
                .execute()
                .value
            self.messages = rows
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Insert into chat_messages (RLS `auth.uid() = sender_id` allows this),
    /// optimistic-append the returned row, then best-effort update
    /// `chat_channels.last_message` / `last_message_at` (policy 026 widens
    /// UPDATE to any authenticated user for these columns).
    public func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            errorMessage = "未登录"
            return
        }

        isSending = true
        defer { isSending = false }

        struct InsertPayload: Encodable {
            let channel_id: String
            let sender_id: String
            let content: String
            let type: String
        }

        do {
            let inserted: ChatMessage = try await client
                .from("chat_messages")
                .insert(InsertPayload(
                    channel_id: channel.id.uuidString,
                    sender_id: userId.uuidString,
                    content: trimmed,
                    type: "text"
                ))
                .select()
                .single()
                .execute()
                .value

            if !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
            }

            struct LastMsgPatch: Encodable {
                let last_message: String
                let last_message_at: String
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            _ = try? await client
                .from("chat_channels")
                .update(LastMsgPatch(last_message: trimmed, last_message_at: iso))
                .eq("id", value: channel.id.uuidString)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Supabase Realtime v2: filtered postgres_changes INSERT stream on
    /// chat_messages for this channel only. Payload is `[String: AnyJSON]`
    /// (JSONObject) — we decode via `JSONObject.decode(as:)` which uses
    /// supabase's configured decoder (handles fractional-second timestamps).
    private func subscribeRealtime() async {
        teardown()  // belt-and-suspenders: never double-subscribe.

        let channelName = "realtime-chat_messages-\(channel.id.uuidString)"
        let ch = client.channel(channelName)
        let changes = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: .eq("channel_id", value: channel.id.uuidString)
        )
        self.realtimeChannel = ch

        do {
            try await ch.subscribeWithError()
        } catch {
            errorMessage = "实时连接失败，新消息可能延迟送达"
            // 不 return —— 依然启动 for-await Task，subscribe 底层重连后会续上
        }

        self.realtimeTask = Task { [weak self] in
            for await change in changes {
                guard let self = self else { return }
                // `JSONObject.decode(as:)` defaults to AnyJSON.decoder which
                // is `JSONDecoder.supabase()` — same one PostgREST uses, so
                // `created_at` / `withdrawn_at` date parsing is consistent
                // with `fetchMessages`.
                if let msg: ChatMessage = try? change.record.decode(as: ChatMessage.self) {
                    await MainActor.run { self.handleRealtimeInsert(msg) }
                }
            }
        }
    }

    private func handleRealtimeInsert(_ row: ChatMessage) {
        // Dedupe against optimistic append from `sendMessage`.
        guard !messages.contains(where: { $0.id == row.id }) else { return }
        messages.append(row)
    }

    public func teardown() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            Task { [client] in await client.removeChannel(ch) }
            realtimeChannel = nil
        }
    }

    deinit {
        realtimeTask?.cancel()
    }
}
