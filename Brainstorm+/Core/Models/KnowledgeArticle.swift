import Foundation

public struct KnowledgeArticle: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let content: String
    public let category: String?
    public let authorId: UUID?
    public let status: ArticleStatus
    public let tags: [String]?
    public let views: Int
    public let createdAt: Date?
    public let updatedAt: Date?

    public enum ArticleStatus: String, Codable, Hashable {
        case draft = "draft"
        case published = "published"
        case archived = "archived"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case category
        case authorId = "author_id"
        case status
        case tags
        case views
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
