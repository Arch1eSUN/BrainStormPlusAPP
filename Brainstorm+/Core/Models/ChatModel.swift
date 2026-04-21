import Foundation

public struct ChatChannel: Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let type: ChannelType
    public let createdBy: UUID?
    public let lastMessage: String?
    public let lastMessageAt: Date?
    public let createdAt: Date?

    public enum ChannelType: String, Codable, Hashable {
        case group = "group"
        case direct = "direct"
        case announcement = "announcement"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case type
        case createdBy = "created_by"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable {
    public let id: UUID
    public let channelId: UUID
    public let senderId: UUID
    public let content: String
    public let type: MessageType
    public let replyTo: UUID?
    // Simplified for MVP, JSONB maps to simple strings or basic Decodable types if needed
    // public let attachments: String? 
    // public let reactions: String?
    public let isWithdrawn: Bool
    public let withdrawnAt: Date?
    public let createdAt: Date?

    public enum MessageType: String, Codable, Hashable {
        case text = "text"
        case image = "image"
        case file = "file"
        case system = "system"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case senderId = "sender_id"
        case content
        case type
        case replyTo = "reply_to"
        case isWithdrawn = "is_withdrawn"
        case withdrawnAt = "withdrawn_at"
        case createdAt = "created_at"
    }
}

public struct ChatChannelMember: Identifiable, Codable, Hashable {
    public let id: UUID
    public let channelId: UUID
    public let userId: UUID
    public let role: MemberRole
    public let joinedAt: Date?

    public enum MemberRole: String, Codable, Hashable {
        case owner
        case admin
        case member
    }

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case userId = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}
