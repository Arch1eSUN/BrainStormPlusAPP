import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Knowledge base CRUD + file attachment port.
//
// Parity targets:
//   fetchKnowledge / fetchCategories / createKnowledge /
//   updateKnowledge / deleteKnowledge
//     → BrainStorm+-Web/src/lib/actions/knowledge.ts
//   File upload
//     → BrainStorm+-Web/src/app/api/knowledge/upload/route.ts
//
// Web semantics we preserve:
//   • fetch: `.order('updated_at', { ascending: false })`, limit 30,
//     optional `.ilike('title', %q%)` + optional `.eq('category', c)`.
//     Crucially, Web does NOT filter on `status` — the old iOS VM
//     did (`.eq("status", "published")`). That filter is dropped.
//   • create: requires title/content/category, stamps author_id and
//     org_id from the caller's profile, views = 0.
//   • update: patches title/content/category (+ optional file_url,
//     file_type, file_size, tags) and bumps updated_at.
//   • delete: hard delete by id; Web's server action is admin-gated
//     via `serverGuard` — iOS hides the buttons behind the same
//     `isAdmin` predicate but the DB row-level policy is the real
//     enforcement (see migration 004).
//
// Web semantics deliberately NOT ported:
//   • The Web file-upload route enqueues a `knowledge_upload`
//     background job that runs PDF parsing and then inserts the
//     `knowledge_articles` row. We can't execute background jobs from
//     iOS, so `uploadFile(...)` uploads the raw file and immediately
//     inserts a row with `title = file.name`, `content = nil`,
//     `file_url/file_type/file_size` set. No PDF text extraction. The
//     server-side parse job is a superset.
//
// AI summary bridge (wired):
//   • `generateAISummary(for:forceRegenerate:)` hits
//     POST /api/mobile/knowledge/ai-summary with a Bearer JWT. That
//     route mirrors `summary-actions.ts::generateKnowledgeSummary` —
//     same prompt, same scenario, same knowledge_articles cache. The
//     VM patches the local `articles[i]` row in place so the detail
//     view re-renders without a full refetch.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class KnowledgeListViewModel: ObservableObject {
    @Published public private(set) var articles: [KnowledgeArticle] = []
    @Published public private(set) var categories: [String] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var isUploading: Bool = false
    /// Per-article AI summary generation flag (keyed by article id).
    /// The detail view uses this to gate its "生成中..." button state.
    @Published public private(set) var generatingSummaryIds: Set<UUID> = []
    @Published public var errorMessage: String?
    @Published public var successMessage: String?
    @Published public var searchText: String = ""
    @Published public var categoryFilter: String? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ──────────────────────────────────────────────────────────────
    // Fetch
    // ──────────────────────────────────────────────────────────────

    /// Mirrors `fetchKnowledge(filters)` + `fetchCategories()` in
    /// knowledge.ts. The two queries run in parallel because the Web
    /// page also loads them with `Promise.all`.
    public func fetchArticles() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categoryFilter?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            async let fetchedArticles: [KnowledgeArticle] = runArticlesQuery(
                search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                category: (category?.isEmpty ?? true) ? nil : category
            )
            async let fetchedCategories: [String] = runCategoriesQuery()

            self.articles = try await fetchedArticles
            self.categories = try await fetchedCategories
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            self.errorMessage = ErrorPresenter.userFacingMessage(error) ?? self.errorMessage
        }
    }

    private func runArticlesQuery(search: String?, category: String?) async throws -> [KnowledgeArticle] {
        // PostgrestFilterBuilder builds immutably on each `.eq`/`.ilike`
        // call, so we have to reassign the chain each time.
        var query = client
            .from("knowledge_articles")
            .select()

        if let category, !category.isEmpty {
            query = query.eq("category", value: category)
        }
        if let search, !search.isEmpty {
            query = query.ilike("title", pattern: "%\(search)%")
        }

        return try await query
            .order("updated_at", ascending: false)
            .limit(30)
            .execute()
            .value
    }

    private func runCategoriesQuery() async throws -> [String] {
        struct CategoryRow: Decodable { let category: String? }
        let rows: [CategoryRow] = try await client
            .from("knowledge_articles")
            .select("category")
            .execute()
            .value
        // Preserve insertion order while de-duping — matches Web's
        // `[...new Set(...)]` over the server response.
        var seen: Set<String> = []
        var result: [String] = []
        for row in rows {
            guard let c = row.category, !c.isEmpty else { continue }
            if seen.insert(c).inserted {
                result.append(c)
            }
        }
        return result
    }

    // ──────────────────────────────────────────────────────────────
    // Create
    // ──────────────────────────────────────────────────────────────

    private struct CreatePayload: Encodable {
        let title: String
        let content: String?
        let category: String
        let tags: [String]?
        let authorId: String
        let orgId: String?
        let views: Int
        let fileUrl: String?
        let fileType: String?
        let fileSize: Int64?

        enum CodingKeys: String, CodingKey {
            case title, content, category, tags, views
            case authorId = "author_id"
            case orgId = "org_id"
            case fileUrl = "file_url"
            case fileType = "file_type"
            case fileSize = "file_size"
        }
    }

    /// 1:1 port of `createKnowledge` from knowledge.ts.
    /// Returns the inserted row on success. Trims inputs and rejects
    /// empty title/category before hitting the network (Web does the
    /// same guard client-side in page.tsx::handleCreate).
    @discardableResult
    public func createArticle(
        title: String,
        content: String?,
        category: String,
        tags: [String]? = nil,
        fileUrl: String? = nil,
        fileType: String? = nil,
        fileSize: Int64? = nil
    ) async -> KnowledgeArticle? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = content?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !t.isEmpty else {
            errorMessage = "请填写文档标题"
            return nil
        }
        guard !cat.isEmpty else {
            errorMessage = "请填写分类"
            return nil
        }
        // File-backed rows are allowed to have no text body (Web accepts
        // this via the background-job path). Inline-authored rows must
        // provide content — matches Web's page.tsx `handleCreate` guard.
        if fileUrl == nil, (body ?? "").isEmpty {
            errorMessage = "请填写文档内容"
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let session = try await client.auth.session
            let uid = session.user.id
            let orgId = try await fetchCurrentOrgId(userId: uid)

            let payload = CreatePayload(
                title: t,
                content: (body?.isEmpty ?? true) ? nil : body,
                category: cat,
                tags: tags,
                authorId: uid.uuidString,
                orgId: orgId?.uuidString,
                views: 0,
                fileUrl: fileUrl,
                fileType: fileType,
                fileSize: fileSize
            )

            let saved: KnowledgeArticle = try await client
                .from("knowledge_articles")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            articles.insert(saved, at: 0)
            if let c = saved.category, !c.isEmpty, !categories.contains(c) {
                categories.append(c)
            }
            successMessage = "文档已发布"
            return saved
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return nil
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Update
    // ──────────────────────────────────────────────────────────────

    private struct UpdatePayload: Encodable {
        let title: String
        let content: String?
        let category: String
        let tags: [String]?
        let fileUrl: String?
        let fileType: String?
        let fileSize: Int64?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case title, content, category, tags
            case fileUrl = "file_url"
            case fileType = "file_type"
            case fileSize = "file_size"
            case updatedAt = "updated_at"
        }
    }

    /// 1:1 port of `updateKnowledge` from knowledge.ts.
    @discardableResult
    public func updateArticle(
        id: UUID,
        title: String,
        content: String?,
        category: String,
        tags: [String]? = nil,
        fileUrl: String? = nil,
        fileType: String? = nil,
        fileSize: Int64? = nil
    ) async -> KnowledgeArticle? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = content?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !t.isEmpty else {
            errorMessage = "请填写文档标题"
            return nil
        }
        guard !cat.isEmpty else {
            errorMessage = "请填写分类"
            return nil
        }
        if fileUrl == nil, (body ?? "").isEmpty {
            errorMessage = "请填写文档内容"
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let payload = UpdatePayload(
                title: t,
                content: (body?.isEmpty ?? true) ? nil : body,
                category: cat,
                tags: tags,
                fileUrl: fileUrl,
                fileType: fileType,
                fileSize: fileSize,
                updatedAt: Self.iso8601Writer.string(from: Date())
            )

            let saved: KnowledgeArticle = try await client
                .from("knowledge_articles")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value

            if let idx = articles.firstIndex(where: { $0.id == saved.id }) {
                articles[idx] = saved
            }
            if let c = saved.category, !c.isEmpty, !categories.contains(c) {
                categories.append(c)
            }
            successMessage = "文档已更新"
            return saved
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
            return nil
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Delete
    // ──────────────────────────────────────────────────────────────

    public func deleteArticle(_ article: KnowledgeArticle) async {
        errorMessage = nil
        do {
            _ = try await client
                .from("knowledge_articles")
                .delete()
                .eq("id", value: article.id.uuidString)
                .execute()
            articles.removeAll { $0.id == article.id }
            successMessage = "文档已删除"
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
        }
    }

    // ──────────────────────────────────────────────────────────────
    // File attachment
    // ──────────────────────────────────────────────────────────────

    /// Upload a file to the `knowledge-files` bucket and create a
    /// new article row that references it. Used by the attach-file
    /// entry in the list toolbar.
    ///
    /// Unlike Web's server route this does NOT:
    ///   - run MIME/signature validation (`upload-validator.ts`)
    ///   - rate-limit by user
    ///   - enqueue a background PDF-parse job
    /// The Supabase bucket config enforces the 100 MB cap + content-
    /// type on the storage side, and the RLS policy enforces admin-
    /// only writes. PDF text extraction is intentionally absent on
    /// iOS — see the `// Web semantics deliberately NOT ported` note
    /// at the top of this file.
    @discardableResult
    public func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        category: String
    ) async -> KnowledgeArticle? {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let (publicURL, _) = try await KnowledgeStorageClient.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                client: client
            )
            let cat = category.trimmingCharacters(in: .whitespacesAndNewlines)
            return await createArticle(
                title: fileName,
                content: nil,
                category: cat.isEmpty ? "未分类" : cat,
                tags: nil,
                fileUrl: publicURL,
                fileType: mimeType,
                fileSize: Int64(data.count)
            )
        } catch {
            errorMessage = "上传失败: \(ErrorLocalizer.localize(error))"
            return nil
        }
    }

    // ──────────────────────────────────────────────────────────────
    // AI summary (bridge)
    // ──────────────────────────────────────────────────────────────

    /// Bridge to POST /api/mobile/knowledge/ai-summary. Mirrors Web's
    /// `generateKnowledgeSummary` — the route handles cache + askAI +
    /// knowledge_articles UPDATE. On success we patch the local
    /// `articles[i]` so the detail view re-renders without a refetch.
    @discardableResult
    public func generateAISummary(
        for article: KnowledgeArticle,
        forceRegenerate: Bool = false
    ) async -> String? {
        // Guard against double-taps on the same article.
        guard !generatingSummaryIds.contains(article.id) else { return nil }
        generatingSummaryIds.insert(article.id)
        errorMessage = nil
        defer { generatingSummaryIds.remove(article.id) }

        do {
            let session = try await client.auth.session
            let token = session.accessToken

            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/knowledge/ai-summary")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 60

            let payload: [String: Any] = [
                "article_id": article.id.uuidString,
                "force_regenerate": forceRegenerate,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "网络异常，请重试"
                return nil
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode >= 400 {
                let msg = (json?["error"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(http.statusCode)"
                errorMessage = "AI 摘要生成失败：\(msg)"
                return nil
            }

            guard let summary = json?["ai_summary"] as? String, !summary.isEmpty else {
                errorMessage = "AI 未返回摘要内容"
                return nil
            }
            let generatedAt = (json?["ai_summary_at"] as? String)
                .flatMap { Self.iso8601Date(from: $0) }
            let model = json?["ai_summary_model"] as? String

            // Patch the local row so detail / card views re-render.
            if let idx = articles.firstIndex(where: { $0.id == article.id }) {
                let existing = articles[idx]
                articles[idx] = KnowledgeArticle(
                    id: existing.id,
                    title: existing.title,
                    content: existing.content,
                    category: existing.category,
                    authorId: existing.authorId,
                    orgId: existing.orgId,
                    status: existing.status,
                    tags: existing.tags,
                    views: existing.views,
                    fileUrl: existing.fileUrl,
                    fileType: existing.fileType,
                    fileSize: existing.fileSize,
                    aiSummary: summary,
                    aiSummaryAt: generatedAt ?? existing.aiSummaryAt ?? Date(),
                    aiSummaryModel: model ?? existing.aiSummaryModel,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt
                )
            }
            return summary
        } catch {
            errorMessage = "AI 摘要生成失败：\(ErrorLocalizer.localize(error))"
            return nil
        }
    }

    /// 共享 ISO8601 formatter（write-path 用：`updatedAt` 序列化）
    private static let iso8601Writer = ISO8601DateFormatter()

    /// 共享 ISO8601 parser（with fractional seconds）——bridge route 返回格式
    private static let iso8601ParserWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601ParserPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Shared parser for the ISO8601-with-fractional-seconds timestamps the
    /// bridge route returns (`new Date().toISOString()`).
    private static func iso8601Date(from raw: String) -> Date? {
        if let d = iso8601ParserWithFraction.date(from: raw) { return d }
        return iso8601ParserPlain.date(from: raw)
    }

    /// Lookup helper for views that only have an article id (used by
    /// the detail view's re-render path after summary generation).
    public func article(withId id: UUID) -> KnowledgeArticle? {
        articles.first { $0.id == id }
    }

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    /// Matches `getCurrentOrgId` in knowledge.ts. We read
    /// profiles.org_id and fall through to nil — the Web admin-fallback
    /// that auto-assigns the first org is intentionally NOT ported
    /// (matches the Reporting VM decision).
    private func fetchCurrentOrgId(userId: UUID) async throws -> UUID? {
        struct Row: Decodable {
            let orgId: UUID?
            enum CodingKeys: String, CodingKey { case orgId = "org_id" }
        }
        let rows: [Row] = try await client
            .from("profiles")
            .select("org_id")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.orgId
    }
}
