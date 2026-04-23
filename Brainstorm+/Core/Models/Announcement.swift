import Foundation
import SwiftUI

// Schema reference: BrainStorm+-Web/supabase/schema.sql:219-229 (announcements),
// BrainStorm+-Web/supabase/migrations/004_schema_alignment.sql:30-36
// (`pinned` alias column + expanded priority enum to include 'important').
// Web uses `pinned` (not legacy `is_pinned`) in
// BrainStorm+-Web/src/lib/actions/announcements.ts; iOS mirrors that.

public struct Announcement: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let content: String
    public let priority: Priority
    public let pinned: Bool
    public let authorId: UUID?
    public let orgId: UUID?
    public let createdAt: Date?
    public let profiles: AuthorProfile?

    public enum Priority: String, Codable, CaseIterable, Hashable {
        case normal
        case important
        case urgent

        public var displayLabel: String {
            switch self {
            case .normal: return "普通"
            case .important: return "重要"
            case .urgent: return "紧急"
            }
        }

        public var tint: Color {
            switch self {
            case .normal: return .secondary
            case .important: return Color.Brand.warning
            case .urgent: return .red
            }
        }
    }

    public struct AuthorProfile: Codable, Hashable {
        public let id: UUID?
        public let fullName: String?
        public let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case priority
        case pinned
        case authorId = "author_id"
        case orgId = "org_id"
        case createdAt = "created_at"
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
        // DB CHECK constraint (migration 004) still permits legacy
        // 'low' / 'high' rows. Fold unknown values to `.normal` so
        // legacy data never blocks the decode.
        let raw = try c.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
        priority = Priority(rawValue: raw) ?? .normal
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        authorId = try c.decodeIfPresent(UUID.self, forKey: .authorId)
        orgId = try c.decodeIfPresent(UUID.self, forKey: .orgId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        profiles = try c.decodeIfPresent(AuthorProfile.self, forKey: .profiles)
    }

    public init(
        id: UUID,
        title: String,
        content: String,
        priority: Priority,
        pinned: Bool,
        authorId: UUID?,
        orgId: UUID? = nil,
        createdAt: Date? = nil,
        profiles: AuthorProfile? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.priority = priority
        self.pinned = pinned
        self.authorId = authorId
        self.orgId = orgId
        self.createdAt = createdAt
        self.profiles = profiles
    }
}
