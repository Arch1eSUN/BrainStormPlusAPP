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
    /// Parent messages referenced by `reply_to`, keyed by parent id.
    /// Populated by `fetchMessages` second-query and kept in sync on realtime
    /// INSERT (if a new message arrives whose reply_to isn't in the lookup,
    /// we backfill it best-effort).
    @Published public var replyLookup: [UUID: ChatMessage] = [:]

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
    /// ORDER BY created_at ASC LIMIT 50, then a second IN-query to hydrate
    /// `reply_to` parents into `replyLookup`. Web does the second query on
    /// the server; iOS does it here so the UI can render reply blocks without
    /// per-row lookups.
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
            await hydrateReplyLookup(for: rows)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Second-query reply-parent fetch. Collects every `reply_to` referenced
    /// by `rows` that we don't already have in `replyLookup`, then issues a
    /// single `IN (...)` select. Missing parents (deleted / RLS-invisible) are
    /// simply absent from the lookup — UI falls back to a "原消息不可用"
    /// placeholder. Parents outside the current channel are intentionally
    /// includable — Web does the same (cross-channel reply is rare but legal).
    private func hydrateReplyLookup(for rows: [ChatMessage]) async {
        let missing: [UUID] = rows.compactMap { $0.replyTo }
            .filter { replyLookup[$0] == nil }
        guard !missing.isEmpty else { return }
        let uniqueIds = Array(Set(missing))
        let idStrings = uniqueIds.map { $0.uuidString }
        do {
            let parents: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .in("id", values: idStrings)
                .execute()
                .value
            for parent in parents {
                replyLookup[parent.id] = parent
            }
        } catch {
            // Non-fatal: reply blocks will degrade to "原消息不可用".
        }
    }

    /// Insert into chat_messages (RLS `auth.uid() = sender_id` allows this),
    /// optimistic-append the returned row, then best-effort update
    /// `chat_channels.last_message` / `last_message_at` (policy 026 widens
    /// UPDATE to any authenticated user for these columns).
    ///
    /// When `attachments` is non-empty, `type` is derived per Web
    /// `sendMessage` (src/lib/actions/chat.ts:595-597): all-images → `image`,
    /// mixed / any non-image → `file`, empty → `text`. `content` mirrors Web
    /// posture — trimmed free-text; empty string is allowed when attachments
    /// are present (sending only images/files is OK).
    public func sendMessage(
        _ text: String,
        attachments: [ChatAttachment] = [],
        replyTo: UUID? = nil
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // empty text AND no attachments → nothing to send
        guard !(trimmed.isEmpty && attachments.isEmpty) else { return }

        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            errorMessage = "未登录"
            return
        }

        isSending = true
        defer { isSending = false }

        let derivedType: String
        if attachments.isEmpty {
            derivedType = "text"
        } else if attachments.allSatisfy({ $0.isImage }) {
            derivedType = "image"
        } else {
            derivedType = "file"
        }

        // `reply_to` is an Optional<String> so PostgREST emits `null` when
        // absent (vs. an empty string that would fail the UUID cast).
        struct InsertPayload: Encodable {
            let channel_id: String
            let sender_id: String
            let content: String
            let type: String
            let attachments: [ChatAttachment]
            let reply_to: String?
        }

        do {
            let inserted: ChatMessage = try await client
                .from("chat_messages")
                .insert(InsertPayload(
                    channel_id: channel.id.uuidString,
                    sender_id: userId.uuidString,
                    content: trimmed,
                    type: derivedType,
                    attachments: attachments,
                    reply_to: replyTo?.uuidString
                ))
                .select()
                .single()
                .execute()
                .value

            // If this message references a parent not in our lookup, backfill
            // it so the reply block renders immediately (can happen if the
            // user replies to a message loaded outside the 50-row window).
            if let parentId = replyTo, replyLookup[parentId] == nil {
                await hydrateReplyLookup(for: [inserted])
            }

            if !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
            }

            // `last_message` preview: Web 展示文本或"[图片]" / "[文件]"。这里
            // 取同样语义 —— 如果有文本就用文本；纯附件则给出通用占位。
            let preview: String
            if !trimmed.isEmpty {
                preview = trimmed
            } else if derivedType == "image" {
                preview = "[图片]"
            } else {
                preview = "[文件]"
            }

            struct LastMsgPatch: Encodable {
                let last_message: String
                let last_message_at: String
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            _ = try? await client
                .from("chat_channels")
                .update(LastMsgPatch(last_message: preview, last_message_at: iso))
                .eq("id", value: channel.id.uuidString)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sprint 3.3: Attachment upload
    //
    // Strategy: iOS uploads directly to the `chat-files` Supabase bucket with a
    // user-JWT. Web uses `createAdminClient()` via `/api/chat/upload/route.ts`,
    // which bypasses `storage.objects` RLS (migration 028:42-58 WITH CHECK
    // `auth.uid()::text = (storage.foldername(name))[1]`). iOS can't bypass,
    // so the path starts with `{user_id}/` to satisfy the policy, then nests
    // `{channel_id}/{uuid}.{ext}` for archival readability. Bucket is public,
    // so reads go through `getPublicURL()` — no signed-URL TTL to manage.
    //
    // Web's page.tsx:288 references a non-existent `chat_attachments` bucket;
    // that client-direct-upload branch is dead Web code (production path is
    // the `/api/chat/upload` route that uploads to `chat-files`). We align
    // with the actual bucket `chat-files`.

    /// Upload a single attachment to `chat-files`. Returns a `ChatAttachment`
    /// ready to be attached to `sendMessage`. Caller chooses MIME (e.g. from
    /// `PhotosPicker` → `image/jpeg`, from `.fileImporter` → `UTType` MIME).
    public func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> ChatAttachment {
        let userId = try await client.auth.session.user.id
        let ext = (fileName as NSString).pathExtension
        let uuid = UUID().uuidString
        let fileComponent = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        let path = "\(userId.uuidString)/\(channel.id.uuidString)/\(fileComponent)"

        _ = try await client.storage
            .from("chat-files")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: false)
            )

        let publicURL = try client.storage
            .from("chat-files")
            .getPublicURL(path: path)

        return ChatAttachment(
            name: fileName,
            url: publicURL.absoluteString,
            type: mimeType,
            size: data.count
        )
    }

    /// Supabase Realtime v2: two filtered postgres_changes streams on
    /// chat_messages for this channel — INSERT (new messages) and UPDATE
    /// (withdraw mutations; chat_messages has no DELETE flow). Both streams
    /// share one WebSocket subscription; Supabase multiplexes by event type.
    ///
    /// Decoding: payload is `[String: AnyJSON]` (JSONObject); we decode via
    /// `JSONObject.decode(as:)` which uses AnyJSON.decoder (== the same
    /// `JSONDecoder.supabase()` PostgREST uses), so `created_at` /
    /// `withdrawn_at` date parsing stays consistent with `fetchMessages`.
    private func subscribeRealtime() async {
        teardown()  // belt-and-suspenders: never double-subscribe.

        let channelName = "realtime-chat_messages-\(channel.id.uuidString)"
        let ch = client.channel(channelName)
        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: .eq("channel_id", value: channel.id.uuidString)
        )
        let updates = ch.postgresChange(
            UpdateAction.self,
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
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await change in inserts {
                        guard let self = self else { return }
                        if let msg: ChatMessage = try? change.record.decode(as: ChatMessage.self) {
                            await MainActor.run { self.handleRealtimeInsert(msg) }
                        }
                    }
                }
                group.addTask { [weak self] in
                    for await change in updates {
                        guard let self = self else { return }
                        if let msg: ChatMessage = try? change.record.decode(as: ChatMessage.self) {
                            await MainActor.run { self.handleRealtimeUpdate(msg) }
                        }
                    }
                }
            }
            _ = self  // silence unused capture warning in case both streams end
        }
    }

    private func handleRealtimeInsert(_ row: ChatMessage) {
        // Dedupe against optimistic append from `sendMessage`.
        guard !messages.contains(where: { $0.id == row.id }) else { return }
        messages.append(row)
        // Backfill parent if this is a reply we haven't seen yet.
        if let parentId = row.replyTo, replyLookup[parentId] == nil {
            Task { await self.hydrateReplyLookup(for: [row]) }
        }
    }

    /// Patch an existing row in-place by id. Used for withdraw UPDATEs from
    /// other devices. If the row isn't in our local window (e.g. scrolled
    /// beyond 50-row limit), we ignore it — it'll re-hydrate on next fetch.
    private func handleRealtimeUpdate(_ row: ChatMessage) {
        if let idx = messages.firstIndex(where: { $0.id == row.id }) {
            messages[idx] = row
        }
        // Also patch replyLookup so child "reply-to" blocks degrade to
        // "消息已撤回" immediately when their parent is withdrawn.
        if replyLookup[row.id] != nil {
            replyLookup[row.id] = row
        }
    }

    // MARK: - Sprint 3.4: Withdraw (撤回)
    //
    // Web `withdrawMessage` (src/lib/actions/chat.ts:702-741) uses
    // `createAdminClient()` (service_role) to UPDATE `chat_messages`
    // because `chat_messages` has NO UPDATE RLS policy. iOS calls PostgREST
    // via user-JWT so we route through a SECURITY DEFINER RPC
    // `chat_withdraw_message` (migration 20260421150000) that replicates
    // Web's server-side checks:
    //   1. caller authenticated
    //   2. caller is original sender
    //   3. not already withdrawn
    //   4. within 2-minute window (Web enforces this client-side only at
    //      page.tsx:386-390; RPC lifts to SQL so it's tamper-proof)
    //
    // On success the RPC mutates content/attachments/is_withdrawn/withdrawn_at;
    // the corresponding realtime UPDATE event will flow through
    // `handleRealtimeUpdate` and patch our local row. We don't optimistically
    // mutate `messages` here — realtime is authoritative.

    public func withdrawMessage(_ messageId: UUID) async {
        struct Params: Encodable {
            let p_message_id: String
        }
        do {
            try await client
                .rpc("chat_withdraw_message", params: Params(p_message_id: messageId.uuidString))
                .execute()
        } catch {
            // RPC raises:
            //   42501 → '未登录'
            //   22023 → '只能撤回自己发送的消息' / '已撤回' / '超过 2 分钟的消息无法撤回'
            //   P0002 → '消息不存在'
            // PostgREST surfaces these in `error.localizedDescription`; UI
            // shows it verbatim so iOS/Web parity holds.
            errorMessage = error.localizedDescription
        }
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
