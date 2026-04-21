import Foundation
import Combine
import Supabase

@MainActor
public class ChatListViewModel: ObservableObject {
    @Published public var channels: [ChatChannel] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

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
            self.errorMessage = error.localizedDescription
        }
    }
}
