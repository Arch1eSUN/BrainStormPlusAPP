import Foundation
import Combine
import Supabase

/// Sprint 3.4: cross-channel message search result. Bundles the raw message
/// with its resolved channel so the UI can render "频道名 › 消息预览" rows
/// without a second lookup.
public struct ChatSearchResult: Identifiable, Hashable {
    public let message: ChatMessage
    public let channel: ChatChannel
    public var id: UUID { message.id }
}

@MainActor
public class ChatListViewModel: ObservableObject {
    @Published public var channels: [ChatChannel] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    // MARK: - Sprint 3.4 search state
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [ChatSearchResult] = []
    @Published public var isSearching: Bool = false

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Mirrors Web `getAccessibleChannelMap` (src/lib/actions/chat.ts:252-282).
    /// Three-part union done client-side because chat_channels SELECT RLS is
    /// `USING (true)`; Web enforces access via server-side admin client.
    ///
    /// Bug-fix(看不见历史对话记录):
    /// 三个 query 改成串行 + per-query 异常隔离 ——
    /// 之前 `async let` 并发 + 单个 catch 兜全部,任何一条 query 抛错(常见
    /// 是 announcement 频道 RLS 在某些组织下没行,或 chat_channel_members
    /// 在 user JWT 下被某些 schema 漂移阻断)整个 fetch 全挂,UI 显示空。
    /// 串行 + 各自 try? 后,即使某一条失败仍能展示其他两条的结果,跟 web
    /// admin client 看到的"任意可访问 channel"语义对齐。
    public func fetchChannels() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            errorMessage = "未登录"
            return
        }

        // 1) Announcement channels —— RLS: type='announcement' 任何登录用户可见
        let anns: [ChatChannel] = await fetchChannelGroup("announcements") {
            try await client
                .from("chat_channels")
                .select()
                .eq("type", value: "announcement")
                .execute()
                .value
        }

        // 2) Owned channels —— created_by = self
        let ownd: [ChatChannel] = await fetchChannelGroup("owned") {
            try await client
                .from("chat_channels")
                .select()
                .eq("created_by", value: currentUserId.uuidString)
                .execute()
                .value
        }

        // 3) Member channels —— 先拿 membership 再批量查 channel
        let memberRows: [ChatChannelMember] = await fetchChannelGroup("memberships") {
            try await client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at")
                .eq("user_id", value: currentUserId.uuidString)
                .execute()
                .value
        }

        var memberChannels: [ChatChannel] = []
        let memberChannelIds = memberRows.map { $0.channelId.uuidString }
        if !memberChannelIds.isEmpty {
            memberChannels = await fetchChannelGroup("memberChannels") {
                try await client
                    .from("chat_channels")
                    .select()
                    .in("id", values: memberChannelIds)
                    .execute()
                    .value
            }
        }

        var seen = Set<UUID>()
        var merged: [ChatChannel] = []
        for ch in anns + ownd + memberChannels {
            if seen.insert(ch.id).inserted { merged.append(ch) }
        }

        merged.sort { a, b in
            switch (a.lastMessageAt, b.lastMessageAt) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
        }

        #if DEBUG
        print("[ChatListViewModel] fetchChannels merged=\(merged.count) anns=\(anns.count) owned=\(ownd.count) member=\(memberChannels.count)")
        #endif

        self.channels = merged

        // 如果三条全空 + 用户也没 membership,给一个明确提示而不是 silent
        // empty(避免用户反馈"消息没和 web 同步"时无从下手 debug)。
        if merged.isEmpty {
            #if DEBUG
            print("[ChatListViewModel] no channels visible to user \(currentUserId.uuidString) — check chat_channels RLS or seeded data")
            #endif
        }
    }

    /// Helper: 每条 query 独立 try,失败 console log 后返回 [],而不是
    /// 让一条挂掉的 query 把整个 fetchChannels 的结果清零。
    private func fetchChannelGroup<T>(
        _ tag: String,
        _ run: () async throws -> [T]
    ) async -> [T] {
        do {
            return try await run()
        } catch {
            #if DEBUG
            print("[ChatListViewModel] fetchChannelGroup(\(tag)) failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    // MARK: - Sprint 3.2: Create conversation / Find-or-create DM
    //
    // Web `createConversation` + `findOrCreateDirectMessage` (src/lib/actions/chat.ts:411, 758)
    // bypass RLS via `createAdminClient()`. iOS uses user-JWT, so those paths are
    // not reachable directly. Sprint 3.2 migration
    // `20260421130000_chat_conversation_rpc.sql` adds two SECURITY DEFINER RPC
    // functions (`chat_find_or_create_direct_channel`, `chat_create_group_channel`)
    // that enforce auth + validation server-side. Both return a channel UUID.

    /// Returns the id of an existing or newly-created direct channel between
    /// the current user and `otherUserId`. Race-safe via the partial unique
    /// index on `chat_channels(participant_pair_key) WHERE type='direct'`.
    public func findOrCreateDirectChannel(with otherUserId: UUID) async throws -> UUID {
        struct Params: Encodable { let p_other_user_id: String }
        // Bug-fix(新建对话失败): 之前 `return try await ...execute().value` 让 Swift
        // 从函数返回类型推 UUID,iOS 26 / Supabase Swift 2.x 在 generic call site
        // 上的类型推断有时会反推成 Void / Data,触发 noResults。改成显式
        // `let id: UUID = ...` 把类型写死,跟 LeaveSubmitViewModel 等其他成功
        // RPC 调用对齐。
        let id: UUID = try await client
            .rpc("chat_find_or_create_direct_channel",
                 params: Params(p_other_user_id: otherUserId.uuidString))
            .execute()
            .value
        return id
    }

    /// Creates a new group channel with the current user as owner and
    /// `memberIds` as regular members. Returns the new channel's id.
    public func createGroupChannel(
        name: String,
        description: String?,
        memberIds: [UUID]
    ) async throws -> UUID {
        struct Params: Encodable {
            let p_name: String
            let p_description: String?
            let p_member_ids: [String]
        }
        // 同 findOrCreateDirectChannel —— 显式 UUID binding 避免推断陷阱
        let id: UUID = try await client
            .rpc("chat_create_group_channel",
                 params: Params(
                    p_name: name,
                    p_description: description,
                    p_member_ids: memberIds.map { $0.uuidString }
                 ))
            .execute()
            .value
        return id
    }

    /// Fetches a channel by id after a create/find RPC, so the caller can
    /// insert the fully-hydrated row into `channels` and navigate into the
    /// room without waiting for a full `fetchChannels()` re-run.
    public func fetchChannel(id: UUID) async throws -> ChatChannel {
        try await client
            .from("chat_channels")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    /// Inserts `channel` into the top of the list if not already present. Used
    /// after create-conversation succeeds so the UI reflects the new channel
    /// without waiting for a full refresh.
    public func appendChannelIfMissing(_ channel: ChatChannel) {
        guard !channels.contains(where: { $0.id == channel.id }) else { return }
        channels.insert(channel, at: 0)
    }

    // MARK: - Sprint 3.4: Cross-channel message search
    //
    // Web has no first-class message search UI — iOS adds this because
    // iPhone screens shove the room-list to the default entry point, so
    // without search users can't find old messages in an announcement
    // they're subscribed to across dozens of groups. Strategy:
    //   1. restrict to accessible channels via `.in("channel_id", ...)` —
    //      uses the union already loaded in `self.channels`, so if the user
    //      searches before `fetchChannels()` completes we return empty.
    //   2. `.ilike("content", "%q%")` — case-insensitive LIKE; Web uses the
    //      same pattern for user search (chat.ts:307-353).
    //   3. order DESC, limit 20 — chat search is exploratory; rank by
    //      recency, don't try to paginate until a user asks.
    //   4. Join channels in-memory so the UI renders "频道 › 消息" without
    //      a second fetch.
    //
    // Withdrawn messages: `content` is overwritten to `'此消息已撤回'` by the
    // withdraw RPC, so they *could* match a query for "撤回". We exclude
    // `is_withdrawn = true` at the DB level so search never surfaces
    // withdrawn messages — mirrors the intent of withdraw (content is gone).

    public func searchMessages(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            // 短查询（0-1 字符）几乎必然全集匹配 —— 直接清掉，避免浪费带宽。
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        let channelIds = channels.map { $0.id.uuidString }
        guard !channelIds.isEmpty else {
            searchResults = []
            return
        }

        do {
            let pattern = "%\(trimmed)%"
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .in("channel_id", values: channelIds)
                .ilike("content", pattern: pattern)
                .eq("is_withdrawn", value: false)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            // In-memory join: channel id → channel.
            let channelLookup = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
            searchResults = rows.compactMap { msg in
                guard let ch = channelLookup[msg.channelId] else { return nil }
                return ChatSearchResult(message: msg, channel: ch)
            }
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            searchResults = []
        }
    }

    /// Mirrors Web `fetchChatUsers` (src/lib/actions/chat.ts:307-353): profile
    /// list excluding self, optionally filtered by name. No org_id scoping
    /// because Web itself doesn't scope — profiles SELECT RLS is assumed to
    /// handle tenant boundaries.
    public func fetchUsers(search: String? = nil) async throws -> [Profile] {
        let currentUserId = try await client.auth.session.user.id
        var builder = client
            .from("profiles")
            .select("id,full_name,display_name,email,avatar_url,department,position")
            .neq("id", value: currentUserId.uuidString)

        if let q = search?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            // Mirrors Web's `full_name.ilike.%q%,display_name.ilike.%q%` OR filter.
            let pattern = "%\(q)%"
            builder = builder.or("full_name.ilike.\(pattern),display_name.ilike.\(pattern)")
        }

        return try await builder
            .order("full_name", ascending: true)
            .limit(50)
            .execute()
            .value
    }
}
