import Foundation
import Combine
import Supabase

// 1:1 port of BrainStorm+-Web/src/lib/actions/announcements.ts:
// fetchAnnouncements / createAnnouncement / togglePin / deleteAnnouncement.
// Web sort: `.order('pinned', asc:false).order('created_at', asc:false)`.
// Write-path authorization is DB-enforced (migration 004:87-91 —
// `Authors can manage announcements` FOR ALL USING role IN
// (super_admin, admin, hr)). iOS hides the controls but the RLS row
// is the actual guard.

@MainActor
public final class AnnouncementsListViewModel: ObservableObject {
    @Published public private(set) var items: [Announcement] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [Announcement] = try await client
                .from("announcements")
                .select("*, profiles:author_id(id, full_name, avatar_url)")
                .order("pinned", ascending: false)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            self.items = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    private struct CreatePayload: Encodable {
        let title: String
        let content: String
        let priority: String
        let pinned: Bool
        let authorId: String

        enum CodingKeys: String, CodingKey {
            case title, content, priority, pinned
            case authorId = "author_id"
        }
    }

    private struct BroadcastNotificationPayload: Encodable {
        let user_id: String
        let title: String
        let body: String
        let type: String
        let link: String
    }

    private struct ProfileIdRow: Decodable { let id: UUID }

    /// Iter5 — 公告 / 广播合并:
    /// 用户反馈 "公告和广播不是一个功能吗为什么拆开了"。我们保留公告的持久化
    /// (announcements 表),并在创建时可选地"推送给所有人"——即 fan-out 到
    /// notifications 表(等同旧 AdminBroadcastView 的行为)。
    /// 失败兜底:公告写入成功 + 推送失败时返回 true(公告已发出),只把推送错误
    /// 写到 errorMessage,避免用户以为整个流程失败。
    private func broadcastAnnouncementToAll(title: String, body: String) async -> (succeeded: Int, error: String?) {
        do {
            let profiles: [ProfileIdRow] = try await client
                .from("profiles")
                .select("id")
                .eq("status", value: "active")
                .execute()
                .value
            guard !profiles.isEmpty else { return (0, "没有活跃用户") }
            let payloads = profiles.map {
                BroadcastNotificationPayload(
                    user_id: $0.id.uuidString,
                    title: title,
                    body: body,
                    type: "info",
                    link: "/dashboard/announcements"
                )
            }
            _ = try await client.from("notifications").insert(payloads).execute()
            return (payloads.count, nil)
        } catch {
            return (0, ErrorLocalizer.localize(error))
        }
    }

    @discardableResult
    public func create(
        title: String,
        content: String,
        priority: Announcement.Priority,
        broadcastToAll: Bool = false
    ) async -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            errorMessage = "请填写公告标题"
            return false
        }
        guard !body.isEmpty else {
            errorMessage = "请填写公告内容"
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let session = try await client.auth.session
            let payload = CreatePayload(
                title: t,
                content: body,
                priority: priority.rawValue,
                pinned: false,
                authorId: session.user.id.uuidString
            )
            let saved: Announcement = try await client
                .from("announcements")
                .insert(payload)
                .select("*, profiles:author_id(id, full_name, avatar_url)")
                .single()
                .execute()
                .value
            items.insert(saved, at: 0)
            // Keep local order consistent with the server sort.
            items.sort { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }

            // Activity log — fire-and-await (non-blocking on failure).
            await ActivityLogWriter.write(
                client: client,
                type: .announcement,
                action: "create_announcement",
                description: "发布了公告「\(t)」",
                entityType: "announcement",
                entityId: saved.id
            )

            // Iter5 — 合并广播：可选地推送给所有活跃用户。
            if broadcastToAll {
                let result = await broadcastAnnouncementToAll(title: t, body: body)
                if let err = result.error {
                    errorMessage = "公告已发布，但推送通知失败：\(err)"
                } else {
                    await ActivityLogWriter.write(
                        client: client,
                        type: .system,
                        action: "broadcast",
                        description: "公告「\(t)」已推送给 \(result.succeeded) 人",
                        entityType: "announcement",
                        entityId: saved.id
                    )
                }
            }
            return true
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    @discardableResult
    public func togglePin(_ announcement: Announcement) async -> Bool {
        let next = !announcement.pinned
        errorMessage = nil
        do {
            _ = try await client
                .from("announcements")
                .update(["pinned": next])
                .eq("id", value: announcement.id.uuidString)
                .execute()
            if let idx = items.firstIndex(where: { $0.id == announcement.id }) {
                let existing = items[idx]
                items[idx] = Announcement(
                    id: existing.id,
                    title: existing.title,
                    content: existing.content,
                    priority: existing.priority,
                    pinned: next,
                    authorId: existing.authorId,
                    orgId: existing.orgId,
                    createdAt: existing.createdAt,
                    profiles: existing.profiles
                )
                items.sort { lhs, rhs in
                    if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                    return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
                }
            }

            // Activity log — pin/unpin counts as an update in Web semantics.
            await ActivityLogWriter.write(
                client: client,
                type: .announcement,
                action: "update_announcement",
                description: "更新了公告「\(announcement.title)」",
                entityType: "announcement",
                entityId: announcement.id
            )
            return true
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    @discardableResult
    public func delete(_ announcement: Announcement) async -> Bool {
        errorMessage = nil
        do {
            _ = try await client
                .from("announcements")
                .delete()
                .eq("id", value: announcement.id.uuidString)
                .execute()
            items.removeAll { $0.id == announcement.id }

            // Activity log — capture title before the row is gone.
            await ActivityLogWriter.write(
                client: client,
                type: .announcement,
                action: "delete_announcement",
                description: "删除了公告「\(announcement.title)」",
                entityType: "announcement",
                entityId: announcement.id
            )
            return true
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }
}
