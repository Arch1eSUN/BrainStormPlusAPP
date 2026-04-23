import Foundation

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Knowledge base row model aligned with Web.
//
// Mirror of the DB columns exercised by
// `BrainStorm+-Web/src/lib/actions/knowledge.ts::KnowledgeDoc` plus the
// file-attachment columns from migration 039 and the AI-summary columns
// from migrations 037 / 013.
//
// `content` is optional (Web types it as `content?: string`) because
// rows created from a file upload ship a `file_url` but no markdown
// body. The iOS read-only list shipped earlier assumed non-optional —
// that's fixed here.
// `status` stays on the model because migration 004 still defines it,
// but the Web fetch path (which the iOS VM now mirrors) does NOT filter
// by it. Decoding is lenient via Optional<String>.
// ══════════════════════════════════════════════════════════════════

public struct KnowledgeArticle: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let content: String?
    public let category: String?
    public let authorId: UUID?
    public let orgId: UUID?
    public let status: String?
    public let tags: [String]?
    public let views: Int
    public let fileUrl: String?
    public let fileType: String?
    public let fileSize: Int64?
    public let aiSummary: String?
    public let aiSummaryAt: Date?
    public let aiSummaryModel: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case category
        case authorId = "author_id"
        case orgId = "org_id"
        case status
        case tags
        case views
        case fileUrl = "file_url"
        case fileType = "file_type"
        case fileSize = "file_size"
        case aiSummary = "ai_summary"
        case aiSummaryAt = "ai_summary_at"
        case aiSummaryModel = "ai_summary_model"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Missing numeric columns on legacy rows should default to zero,
    /// not fail the whole list decode. Matches Web's defensive read.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        authorId = try c.decodeIfPresent(UUID.self, forKey: .authorId)
        orgId = try c.decodeIfPresent(UUID.self, forKey: .orgId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        views = (try? c.decode(Int.self, forKey: .views)) ?? 0
        fileUrl = try c.decodeIfPresent(String.self, forKey: .fileUrl)
        fileType = try c.decodeIfPresent(String.self, forKey: .fileType)
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize)
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
        aiSummaryAt = try c.decodeIfPresent(Date.self, forKey: .aiSummaryAt)
        aiSummaryModel = try c.decodeIfPresent(String.self, forKey: .aiSummaryModel)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public init(
        id: UUID,
        title: String,
        content: String?,
        category: String?,
        authorId: UUID?,
        orgId: UUID? = nil,
        status: String? = nil,
        tags: [String]? = nil,
        views: Int = 0,
        fileUrl: String? = nil,
        fileType: String? = nil,
        fileSize: Int64? = nil,
        aiSummary: String? = nil,
        aiSummaryAt: Date? = nil,
        aiSummaryModel: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.authorId = authorId
        self.orgId = orgId
        self.status = status
        self.tags = tags
        self.views = views
        self.fileUrl = fileUrl
        self.fileType = fileType
        self.fileSize = fileSize
        self.aiSummary = aiSummary
        self.aiSummaryAt = aiSummaryAt
        self.aiSummaryModel = aiSummaryModel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
