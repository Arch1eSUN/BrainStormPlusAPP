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

        do {
            async let announcements: [ChatChannel] = client
                .from("chat_channels")
                .select()
                .eq("type", value: "announcement")
                .execute()
                .value

            async let owned: [ChatChannel] = client
                .from("chat_channels")
                .select()
                .eq("created_by", value: currentUserId.uuidString)
                .execute()
                .value

            async let memberships: [ChatChannelMember] = client
                .from("chat_channel_members")
                .select("id,channel_id,user_id,role,joined_at")
                .eq("user_id", value: currentUserId.uuidString)
                .execute()
                .value

            let (anns, ownd, memberRows) = try await (announcements, owned, memberships)

            var memberChannels: [ChatChannel] = []
            let memberChannelIds = memberRows.map { $0.channelId.uuidString }
            if !memberChannelIds.isEmpty {
                memberChannels = try await client
                    .from("chat_channels")
                    .select()
                    .in("id", values: memberChannelIds)
                    .execute()
                    .value
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

            self.channels = merged
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
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
        return try await client
            .rpc("chat_find_or_create_direct_channel",
                 params: Params(p_other_user_id: otherUserId.uuidString))
            .execute()
            .value
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
        return try await client
            .rpc("chat_create_group_channel",
                 params: Params(
                    p_name: name,
                    p_description: description,
                    p_member_ids: memberIds.map { $0.uuidString }
                 ))
            .execute()
            .value
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
