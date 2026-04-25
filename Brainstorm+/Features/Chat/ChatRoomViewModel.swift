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

    // MARK: - Phase 1.1 (slack-grade) state

    /// 未读分隔线锚点 —— 进入频道时记下当前 last_read_at,在第一条
    /// created_at > unreadAnchor 的消息上方插 UnreadDividerView。进入后我们
    /// 不实时更新 anchor(否则 divider 会跳),只在用户下次进入时刷新。
    @Published public var unreadAnchor: Date? = nil

    /// 输入栏当前文本(草稿) —— View 把 TextEditor 绑到这里。debounced 写入
    /// @AppStorage + chat_save_draft RPC。
    @Published public var draft: String = ""

    /// 频道内可 mention 成员清单 —— 进入频道时拉一次,@ 触发 sheet 时不再
    /// 发请求。Web 行为相同(预拉成员)。
    @Published public var mentionCandidates: [Profile] = []

    /// 用户是否处于"贴底"状态。新消息到达时若 isAtBottom == true,自动滚动到
    /// 底;否则显示 "新消息 ↓" pill。View 通过 ScrollView geometry 推送状态。
    @Published public var isAtBottom: Bool = true

    /// 用户离开底部后到达的新消息累计计数 —— 显示在 "新消息 ↓" pill 上。
    @Published public var pendingBelowCount: Int = 0

    /// Phase 1.1: 当前用户在该 channel 的 member 行 —— 只用 last_read_at。
    /// announcement / created_by 频道用户可能没显式 member 行,此时为 nil
    /// (chat_mark_read RPC 会 upsert 出来)。
    @Published public var memberRow: ChatChannelMember? = nil

    private let client: SupabaseClient
    public let channel: ChatChannel

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    /// Phase 1.1: 草稿写入 debounce —— 用户连续敲键盘时,500ms idle 后才推。
    private var draftSaveTask: Task<Void, Never>?

    /// Phase 1.1: chat_mark_read 的 debounce —— 用户在 viewport 内滑过 divider,
    /// 1s idle 后才推。避免每条新消息都打一发 RPC。
    private var markReadTask: Task<Void, Never>?

    // MARK: - Iter 7 Phase 1.2 state

    /// Realtime typing presence — user_id → (display_name, last_event_ts).
    /// Pruned on a 1s timer (entries older than 3s drop out automatically).
    @Published public var typingUsers: [UUID: TypingUser] = [:]

    /// 当前正在编辑的消息 id —— UI 据此把对应 bubble 替换成 inline TextField。
    @Published public var editingMessageId: UUID? = nil
    @Published public var editingDraft: String = ""

    /// Cursor pagination (infinite scroll up) —— 50 条/页。loadMoreOlder 用
    /// `created_at < oldestLoadedAt` 拉下一页。`hasMoreOlder == false` 时
    /// 用户滑到顶不再触发 fetch。
    @Published public var hasMoreOlder: Bool = true
    @Published public var isLoadingOlder: Bool = false

    /// Per-message link preview cache —— message id → first URL → ScrapeResult.
    /// 跨 message 复用同一个 cache key (URL),减少重复 fetch。
    @Published public var linkPreviews: [URL: ChatLinkPreview] = [:]

    private let pageSize = 50

    /// Typing broadcast channel + send debounce.
    private var typingChannel: RealtimeChannelV2?
    private var typingTask: Task<Void, Never>?
    private var typingSendTask: Task<Void, Never>?
    private var typingPruneTimer: Timer?
    private var lastTypingSent: Date?
    private lazy var service: MessagesService = MessagesService(client: client)

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
            await loadMemberRow(userId: userId)  // 可能为 nil(announcement)
            await fetchMessages()
            await subscribeRealtime()
            await subscribeTyping()
            await loadDraft()
            await loadMentionCandidates()
            return
        }

        do {
            let rows: [ChatChannelMember] = try await client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at,last_read_at,muted_until,pinned_at")
                .eq("channel_id", value: channel.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            if rows.isEmpty {
                accessDenied = true
                return
            }
            memberRow = rows.first
            unreadAnchor = rows.first?.lastReadAt
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            accessDenied = true
            return
        }

        await fetchMessages()
        await subscribeRealtime()
        await subscribeTyping()
        await loadDraft()
        await loadMentionCandidates()
    }

    /// Phase 1.1 — 加载 announcement / created_by 频道下的隐式 member 行(可能不存在)。
    private func loadMemberRow(userId: UUID) async {
        do {
            let rows: [ChatChannelMember] = try await client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at,last_read_at,muted_until,pinned_at")
                .eq("channel_id", value: channel.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            memberRow = rows.first
            unreadAnchor = rows.first?.lastReadAt
        } catch {
            // 非致命:announcement 频道 RLS 下可能查不到 —— 走 nil(整 channel
            // 视为已读,不画 divider)。
            memberRow = nil
            unreadAnchor = nil
        }
    }

    /// Matches Web `fetchMessages` (src/lib/actions/chat.ts:539-576):
    /// ORDER BY created_at DESC LIMIT 50 (newest first cursor anchor), then
    /// reverse to ASC for display, then a second IN-query to hydrate
    /// `reply_to` parents into `replyLookup`.
    ///
    /// Iter 7 Phase 1.2 — switched to DESC + reverse so the cursor pagination
    /// (`loadMoreOlderMessages`) anchors on the oldest loaded created_at and
    /// fetches the next 50 below it. Web still uses ASC; iOS diverges because
    /// chat scroll is naturally bottom-anchored on phones.
    public func fetchMessages() async {
        do {
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("channel_id", value: channel.id.uuidString)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
            // 翻转回 ASC 让 UI 顺序自上而下(老→新)。
            let asc = rows.reversed().map { $0 }
            // Phase 1.1: 主流不展示 thread 子消息(reply_to 非空)。子消息进
            // ChatThreadView 展示。父消息保留,显示 thread footer "n 条回复 →"。
            self.messages = asc.filter { $0.replyTo == nil }
            self.hasMoreOlder = (rows.count >= pageSize)
            await hydrateReplyLookup(for: asc)
        } catch {
            if let msg = ErrorPresenter.userFacingMessage(error) {
                self.errorMessage = msg
            }
        }
    }

    /// Iter 7 Phase 1.2 — infinite scroll up. Fetch next page older than
    /// the oldest loaded message. No-op if already loading or no more.
    public func loadMoreOlderMessages() async {
        guard hasMoreOlder, !isLoadingOlder else { return }
        guard let oldest = messages.first?.createdAt else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        // We use string-form ISO8601 because PostgREST's `.lt` on timestamptz
        // expects ISO timestamps, not Date objects.
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cursor = isoFmt.string(from: oldest)

        do {
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("channel_id", value: channel.id.uuidString)
                .lt("created_at", value: cursor)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
            let asc = rows.reversed().map { $0 }
            let topLevel = asc.filter { $0.replyTo == nil }
            // Prepend, dedupe by id (defensive against overlap with cursor edge).
            let existing = Set(messages.map { $0.id })
            let newOnes = topLevel.filter { !existing.contains($0.id) }
            self.messages = newOnes + self.messages
            self.hasMoreOlder = (rows.count >= pageSize)
            await hydrateReplyLookup(for: asc)
        } catch {
            // best-effort: 顶部 retry banner 不引入,silently 让 sentinel 之后再触发
            #if DEBUG
            print("[ChatRoomViewModel] loadMoreOlderMessages failed: \(error.localizedDescription)")
            #endif
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
            // iter6 §B.2 — silent on cancellation (view leave / re-task).
            if let msg = ErrorPresenter.userFacingMessage(error) {
                errorMessage = msg
            }
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
        // Phase 1.1: thread 回复(reply_to 非空)不进入主流,但需要把父消息的
        // thread_reply_count 乐观 +1 让 footer 立即更新。
        if let parentId = row.replyTo {
            if let idx = messages.firstIndex(where: { $0.id == parentId }) {
                let m = messages[idx]
                messages[idx] = ChatMessage(
                    id: m.id, channelId: m.channelId, senderId: m.senderId,
                    content: m.content, type: m.type, replyTo: m.replyTo,
                    attachments: m.attachments, reactions: m.reactions,
                    isWithdrawn: m.isWithdrawn, withdrawnAt: m.withdrawnAt,
                    createdAt: m.createdAt,
                    threadReplyCount: m.threadReplyCount + 1
                )
            }
            if replyLookup[parentId] == nil {
                Task { await self.hydrateReplyLookup(for: [row]) }
            }
            return
        }

        // Dedupe against optimistic append from `sendMessage`.
        guard !messages.contains(where: { $0.id == row.id }) else { return }
        messages.append(row)

        // Phase 1.1: 用户不在底部时,累计 "新消息 ↓" pill 计数。本人发的不计。
        if !isAtBottom && row.senderId != currentUserId {
            pendingBelowCount += 1
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
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Phase 4.5: Reactions (emoji toggle)
    //
    // Web `toggleMessageReaction` (chat.ts:656-700) uses service_role to
    // mutate `reactions` JSONB column. iOS routes through
    // `chat_toggle_message_reaction` RPC (parked migration
    // 20260423000000_chat_toggle_reaction_rpc.sql) for the same reason as
    // withdraw: chat_messages has no UPDATE RLS policy. Optimistic UI:
    // we locally flip the caller's id in/out of `reactions[emoji]`, then
    // rely on the realtime UPDATE (handleRealtimeUpdate) to reconcile with
    // server truth. If the RPC fails the banner surfaces and the next
    // realtime UPDATE / fetch will snap state back.

    public func toggleReaction(messageId: UUID, emoji: String) async {
        guard let me = currentUserId else {
            errorMessage = "未登录"
            return
        }

        // Optimistic toggle in local messages array.
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            var reactions = messages[idx].reactions
            var users = reactions[emoji] ?? []
            if let existing = users.firstIndex(of: me) {
                users.remove(at: existing)
            } else {
                users.append(me)
            }
            if users.isEmpty {
                reactions.removeValue(forKey: emoji)
            } else {
                reactions[emoji] = users
            }
            messages[idx] = ChatMessage(
                id: messages[idx].id,
                channelId: messages[idx].channelId,
                senderId: messages[idx].senderId,
                content: messages[idx].content,
                type: messages[idx].type,
                replyTo: messages[idx].replyTo,
                attachments: messages[idx].attachments,
                reactions: reactions,
                isWithdrawn: messages[idx].isWithdrawn,
                withdrawnAt: messages[idx].withdrawnAt,
                createdAt: messages[idx].createdAt
            )
        }

        struct Params: Encodable {
            let p_message_id: String
            let p_emoji: String
        }
        do {
            try await client
                .rpc("chat_toggle_message_reaction",
                     params: Params(p_message_id: messageId.uuidString, p_emoji: emoji))
                .execute()
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            // Best-effort rollback: re-fetch the row; realtime UPDATE may
            // already have reconciled but this belts the suspenders.
            await refetchMessage(id: messageId)
        }
    }

    /// Re-fetches a single message and patches it into `messages` in place.
    /// Used as a rollback after a failed optimistic mutation (reactions).
    private func refetchMessage(id: UUID) async {
        do {
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            if let fresh = rows.first, let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx] = fresh
            }
        } catch {
            // Non-fatal: next fetch / realtime will reconcile.
        }
    }

    // MARK: - Phase 1.1: Drafts

    /// 启动 / 视图重入时调用 —— 优先取 RPC 跨设备值,RPC 失败则保持空(View
    /// 那边的 @AppStorage per-device 值已经填进 draft binding 之前)。
    public func loadDraft() async {
        struct Params: Encodable { let p_channel_id: String }
        do {
            let content: String = try await client
                .rpc("chat_get_draft", params: Params(p_channel_id: channel.id.uuidString))
                .execute()
                .value
            // 仅当本地还没草稿时才覆盖,避免压掉用户刚刚在另一设备开始打的字。
            if draft.isEmpty && !content.isEmpty {
                draft = content
            }
        } catch {
            // 非致命:草稿是 best-effort,失败让 View 保持空 / @AppStorage 值。
        }
    }

    /// View 监听 draft 变化时调用(debounced 500ms)。
    public func saveDraftDebounced(_ text: String) {
        draftSaveTask?.cancel()
        let channelId = channel.id.uuidString
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self = self, !Task.isCancelled else { return }
            struct Params: Encodable {
                let p_channel_id: String
                let p_content: String
            }
            do {
                try await self.client
                    .rpc("chat_save_draft", params: Params(p_channel_id: channelId, p_content: text))
                    .execute()
            } catch {
                // best-effort
            }
        }
    }

    /// Send 成功后调用,清掉服务端草稿(同时 View 那边也会清 @AppStorage)。
    public func clearDraftRemote() async {
        struct Params: Encodable { let p_channel_id: String }
        do {
            try await client
                .rpc("chat_clear_draft", params: Params(p_channel_id: channel.id.uuidString))
                .execute()
        } catch { /* best-effort */ }
    }

    // MARK: - Phase 1.1: Mark read

    /// 用户停留在底部 / 视图在前台时,1s idle 推进 last_read_at 到 messages.last.id。
    public func markReadDebounced() {
        markReadTask?.cancel()
        guard let lastMessage = messages.last else { return }
        let channelId = channel.id.uuidString
        let messageId = lastMessage.id.uuidString
        markReadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            struct Params: Encodable {
                let p_channel_id: String
                let p_message_id: String
            }
            do {
                try await self.client
                    .rpc("chat_mark_read",
                         params: Params(p_channel_id: channelId, p_message_id: messageId))
                    .execute()
                // 不更新 unreadAnchor —— 下次进入频道时再 refresh,以免本次 session
                // 内 divider 突然消失。
            } catch {
                // best-effort
            }
        }
    }

    // MARK: - Phase 1.1: Mention candidates

    /// 拉频道内的成员 + 兜底 active profiles(announcement 频道下没显式 member 行)。
    /// 50 条上限,UI 侧再做模糊过滤。
    public func loadMentionCandidates() async {
        do {
            // 先拿 channel members 的 user_id
            let memberRows: [ChatChannelMember] = try await client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at")
                .eq("channel_id", value: channel.id.uuidString)
                .limit(200)
                .execute()
                .value

            let memberIds = memberRows.map { $0.userId.uuidString }
            if memberIds.isEmpty {
                // 全频道(announcement) —— 退而拉前 50 个 active profiles。
                let profiles: [Profile] = try await client
                    .from("profiles")
                    .select("id,full_name,display_name,email,avatar_url,department,position")
                    .order("full_name", ascending: true)
                    .limit(50)
                    .execute()
                    .value
                self.mentionCandidates = profiles.filter { $0.id != currentUserId }
                return
            }

            let profiles: [Profile] = try await client
                .from("profiles")
                .select("id,full_name,display_name,email,avatar_url,department,position")
                .in("id", values: memberIds)
                .execute()
                .value
            self.mentionCandidates = profiles.filter { $0.id != currentUserId }
        } catch {
            // 非致命 —— @ sheet 会显示空态。
        }
    }

    // MARK: - Iter 7 Phase 1.2: Typing presence (Realtime broadcast)
    //
    // Channel pattern: `chat-typing-{channelId}`. We broadcast `{user_id,
    // name, ts}` debounced 1s while the user is composing; receivers prune
    // entries older than 3s so dead clients fade naturally.

    private func subscribeTyping() async {
        guard typingChannel == nil else { return }
        let name = "chat-typing-\(channel.id.uuidString)"
        let ch = client.channel(name)
        let stream = ch.broadcastStream(event: "typing")
        self.typingChannel = ch

        do {
            try await ch.subscribeWithError()
        } catch {
            // 实时连接失败时,typing 退化为静默 —— 不画 typing indicator,主消息
            // 流的 realtime 已经独立工作,不需要重试。
            return
        }

        self.typingTask = Task { [weak self] in
            for await msg in stream {
                guard let self = self else { return }
                // payload: {"user_id":"...", "name":"...", "ts": 12345}
                guard let userIdStr = msg["user_id"]?.stringValue,
                      let userId = UUID(uuidString: userIdStr),
                      let name = msg["name"]?.stringValue else { continue }
                if userId == self.currentUserId { continue }   // skip self
                await MainActor.run {
                    self.typingUsers[userId] = TypingUser(
                        id: userId,
                        name: name,
                        lastSeen: Date()
                    )
                }
            }
        }

        // Prune timer — drop entries older than 3s.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let cutoff = Date().addingTimeInterval(-3)
                self.typingUsers = self.typingUsers.filter { $0.value.lastSeen > cutoff }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.typingPruneTimer = timer
    }

    /// Caller-driven: while user is typing the input bar fires this every
    /// keystroke. We rate-limit broadcast to 1 per 800ms so we don't flood
    /// the channel.
    public func notifyTyping() {
        guard let me = currentUserId else { return }
        guard let ch = typingChannel else { return }

        let now = Date()
        if let last = lastTypingSent, now.timeIntervalSince(last) < 0.8 {
            return
        }
        lastTypingSent = now

        let name = currentUserDisplayName ?? "成员"
        typingSendTask?.cancel()
        typingSendTask = Task {
            let payload: JSONObject = [
                "user_id": .string(me.uuidString),
                "name": .string(name),
                "ts": .double(now.timeIntervalSince1970)
            ]
            await ch.broadcast(event: "typing", message: payload)
        }
    }

    /// Best-effort display name resolved from mentionCandidates / fallback to
    /// "成员". Used for outgoing typing payload only.
    private var currentUserDisplayName: String? {
        if let me = currentUserId,
           let prof = mentionCandidates.first(where: { $0.id == me }) {
            return prof.fullName ?? prof.displayName
        }
        return nil
    }

    // MARK: - Iter 7 Phase 1.2: Read receipt (per message)

    /// Called by MessageBubbleView.onAppear (debounced 500ms via Task sleep).
    /// Calls chat_mark_read which advances last_read_at *and* appends user_id
    /// to the per-message read_by JSONB. Skips if already in read_by.
    public func markMessageRead(_ messageId: UUID) async {
        guard let me = currentUserId else { return }
        // Don't mark our own messages.
        if let m = messages.first(where: { $0.id == messageId }), m.senderId == me {
            return
        }
        // Skip if our id is already there (idempotent — RPC also no-ops, but
        // saving the round-trip is nice).
        if let m = messages.first(where: { $0.id == messageId }), m.readBy.contains(me) {
            return
        }
        struct Params: Encodable {
            let p_channel_id: String
            let p_message_id: String
        }
        do {
            try await client
                .rpc("chat_mark_read",
                     params: Params(p_channel_id: channel.id.uuidString,
                                    p_message_id: messageId.uuidString))
                .execute()
            // Optimistic local patch — append our id to the row's read_by so
            // the avatar stack updates without waiting for realtime.
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                let m = messages[idx]
                guard !m.readBy.contains(me) else { return }
                let patched = ChatMessage(
                    id: m.id, channelId: m.channelId, senderId: m.senderId,
                    content: m.content, type: m.type, replyTo: m.replyTo,
                    attachments: m.attachments, reactions: m.reactions,
                    isWithdrawn: m.isWithdrawn, withdrawnAt: m.withdrawnAt,
                    createdAt: m.createdAt, threadReplyCount: m.threadReplyCount,
                    editedAt: m.editedAt, readBy: m.readBy + [me]
                )
                messages[idx] = patched
            }
        } catch {
            // best-effort
        }
    }

    // MARK: - Iter 7 Phase 1.2: Edit message (5-min window)

    public func beginEditing(_ messageId: UUID) {
        guard let m = messages.first(where: { $0.id == messageId }) else { return }
        guard m.senderId == currentUserId else { return }
        editingMessageId = messageId
        editingDraft = m.content
    }

    public func cancelEditing() {
        editingMessageId = nil
        editingDraft = ""
    }

    public func commitEdit() async {
        guard let id = editingMessageId else { return }
        let newContent = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        // Optimistic patch — patches will reconcile via realtime UPDATE.
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let m = messages[idx]
            messages[idx] = ChatMessage(
                id: m.id, channelId: m.channelId, senderId: m.senderId,
                content: newContent, type: m.type, replyTo: m.replyTo,
                attachments: m.attachments, reactions: m.reactions,
                isWithdrawn: m.isWithdrawn, withdrawnAt: m.withdrawnAt,
                createdAt: m.createdAt, threadReplyCount: m.threadReplyCount,
                editedAt: Date(), readBy: m.readBy
            )
        }

        do {
            try await service.editMessage(messageId: id, newContent: newContent)
            cancelEditing()
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            // Revert by refetching the row.
            await refetchMessage(id: id)
        }
    }

    /// True iff this message is editable (own + within 5 min + not withdrawn).
    public func canEdit(_ msg: ChatMessage) -> Bool {
        guard msg.senderId == currentUserId else { return false }
        guard !msg.isWithdrawn else { return false }
        guard let created = msg.createdAt else { return false }
        return Date().timeIntervalSince(created) < 5 * 60
    }

    public func teardown() {
        realtimeTask?.cancel()
        realtimeTask = nil
        draftSaveTask?.cancel()
        markReadTask?.cancel()
        typingTask?.cancel()
        typingSendTask?.cancel()
        typingPruneTimer?.invalidate()
        typingPruneTimer = nil
        if let ch = realtimeChannel {
            Task { [client] in await client.removeChannel(ch) }
            realtimeChannel = nil
        }
        if let ch = typingChannel {
            Task { [client] in await client.removeChannel(ch) }
            typingChannel = nil
        }
    }

    deinit {
        realtimeTask?.cancel()
        draftSaveTask?.cancel()
        markReadTask?.cancel()
        typingTask?.cancel()
        typingSendTask?.cancel()
        typingPruneTimer?.invalidate()
    }
}

/// Phase 1.2 — typing presence record.
public struct TypingUser: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let lastSeen: Date
}

/// Phase 1.2 — link preview cache entry.
public struct ChatLinkPreview: Hashable, Identifiable {
    public let url: URL
    public let title: String?
    public let description: String?
    public let imageURL: URL?
    public let siteName: String?
    public var id: URL { url }

    public init(url: URL, title: String?, description: String?, imageURL: URL?, siteName: String?) {
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }
}
