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

/// Web `ChatAttachment` 1:1 mirror (src/lib/actions/chat.ts:5-10).
/// Stored as JSONB array in `chat_messages.attachments`. Empty array means
/// text-only message. Reactions stay out of iOS scope for now.
public struct ChatAttachment: Codable, Hashable {
    public let name: String
    public let url: String
    public let type: String   // MIME, e.g. "image/png", "application/pdf"
    public let size: Int?

    public var isImage: Bool { type.hasPrefix("image/") }

    public init(name: String, url: String, type: String, size: Int?) {
        self.name = name
        self.url = url
        self.type = type
        self.size = size
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable {
    public let id: UUID
    public let channelId: UUID
    public let senderId: UUID
    public let content: String
    public let type: MessageType
    public let replyTo: UUID?
    public let attachments: [ChatAttachment]
    /// Phase 4.5: `reactions` JSONB map `{ "👍": ["uuid1", "uuid2"], … }` 对齐
    /// Web `chat_messages.reactions` (migration 028:8). 空 map 用 `{}`；
    /// 撤回消息 Web 故意保留 reactions（chat.ts 注释），iOS 同步策略。
    public let reactions: [String: [UUID]]
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
        case attachments
        case reactions
        case isWithdrawn = "is_withdrawn"
        case withdrawnAt = "withdrawn_at"
        case createdAt = "created_at"
    }

    // JSONB 默认值是 '[]' 但旧行 / 非 SELECT 实时事件里有可能字段缺席，
    // 所以自定义 decoder 把缺席 / null 都归一成空数组 —— Web
    // `normalizeAttachments` (chat.ts:169-185) 也是同样的容错姿势。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        channelId = try c.decode(UUID.self, forKey: .channelId)
        senderId = try c.decode(UUID.self, forKey: .senderId)
        content = try c.decode(String.self, forKey: .content)
        type = try c.decode(MessageType.self, forKey: .type)
        replyTo = try c.decodeIfPresent(UUID.self, forKey: .replyTo)
        attachments = (try? c.decodeIfPresent([ChatAttachment].self, forKey: .attachments)) ?? []
        // reactions 字段可能缺席 (旧行 / realtime minimal payload) → 降级为空
        if let raw = try? c.decodeIfPresent([String: [UUID]].self, forKey: .reactions) {
            reactions = raw
        } else {
            // 兜底：旧行 reactions 可能是 String 数组形式的 ID，或其他结构；失败就清零。
            reactions = [:]
        }
        isWithdrawn = try c.decode(Bool.self, forKey: .isWithdrawn)
        withdrawnAt = try c.decodeIfPresent(Date.self, forKey: .withdrawnAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public init(
        id: UUID,
        channelId: UUID,
        senderId: UUID,
        content: String,
        type: MessageType,
        replyTo: UUID? = nil,
        attachments: [ChatAttachment] = [],
        reactions: [String: [UUID]] = [:],
        isWithdrawn: Bool = false,
        withdrawnAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.senderId = senderId
        self.content = content
        self.type = type
        self.replyTo = replyTo
        self.attachments = attachments
        self.reactions = reactions
        self.isWithdrawn = isWithdrawn
        self.withdrawnAt = withdrawnAt
        self.createdAt = createdAt
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
