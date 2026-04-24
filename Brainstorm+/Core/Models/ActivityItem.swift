import Foundation

// ══════════════════════════════════════════════════════════════════
// Phase 3 — 1:1 port of the Web `ActivityItem` shape.
//
// Schema reference:
//   supabase/schema.sql ≈ L275 (public.activity_log)
//   BrainStorm+-Web/src/lib/actions/activity.ts L8-L17
//
// Web select (activity.ts L24-L28):
//   .from('activity_log')
//   .select('*, profiles:user_id(full_name, avatar_url)')
//   .order('created_at', { ascending: false })
//   .limit(limit)
//
// Nullable columns per schema:
//   user_id     nullable (system-emitted rows can be authorless)
//   target_id   nullable
//   description defaults to '' but column allows empty string, not null
//   type        defaults to 'system'; Web treats unknown types as 'system'
//   profiles    nullable when user_id is null OR join misses
// ══════════════════════════════════════════════════════════════════

public struct ActivityItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public let type: ActivityType
    public let action: String
    public let description: String
    public let userId: UUID?
    public let targetId: UUID?
    public let createdAt: Date
    public let profiles: ActivityActor?

    public enum ActivityType: String, Codable, Hashable, CaseIterable {
        case task
        case leave
        case project
        case announcement
        case okr
        case attendance
        case approval
        case system

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            self = ActivityType(rawValue: raw) ?? .system
        }
    }

    public struct ActivityActor: Codable, Hashable {
        public let fullName: String?
        public let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case action
        case description
        case userId = "user_id"
        case targetId = "target_id"
        case createdAt = "created_at"
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.type = (try c.decodeIfPresent(ActivityType.self, forKey: .type)) ?? .system
        self.action = (try c.decodeIfPresent(String.self, forKey: .action)) ?? ""
        self.description = (try c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        self.userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        self.targetId = try c.decodeIfPresent(UUID.self, forKey: .targetId)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.profiles = try c.decodeIfPresent(ActivityActor.self, forKey: .profiles)
    }
}
