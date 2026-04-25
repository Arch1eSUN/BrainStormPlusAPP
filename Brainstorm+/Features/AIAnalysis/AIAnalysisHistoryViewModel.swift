import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// AIAnalysisHistoryViewModel — Round 50 fix #2
//
// Owns paginated reads of `ai_analysis_history` (RLS owner-only) and
// row deletes. Page size = 20; lazy loadMore on scroll-end.
//
// Direct Supabase reads are deliberate: this is a per-user feed where
// RLS already does the auth gate, so a Web /api round-trip would just add
// latency without security value.
// ══════════════════════════════════════════════════════════════════

public struct AIAnalysisHistoryItem: Identifiable, Decodable, Equatable, Hashable {
    public let id: String
    public let platform: String?
    public let sourceUrl: String?
    public let uploadedImageUrls: [String]?
    public let scrapedData: AnyJSON?
    public let aiReport: AnyJSON?
    public let aiRawResponse: String?
    public let status: String
    public let errorMessage: String?
    public let durationMs: Int?
    public let modelUsed: String?
    public let costEstimateCents: Int?
    public let createdAt: String
    public let title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case sourceUrl = "source_url"
        case uploadedImageUrls = "uploaded_image_urls"
        case scrapedData = "scraped_data"
        case aiReport = "ai_report"
        case aiRawResponse = "ai_raw_response"
        case status
        case errorMessage = "error_message"
        case durationMs = "duration_ms"
        case modelUsed = "model_used"
        case costEstimateCents = "cost_estimate_cents"
        case createdAt = "created_at"
        case title
    }

    // ── Display helpers ────────────────────────────────────────

    public var platformLabel: String {
        switch platform ?? "other" {
        case "douyin": return "抖音"
        case "kuaishou": return "快手"
        case "xiaohongshu": return "小红书"
        case "weibo": return "微博"
        case "bilibili": return "B 站"
        case "tiktok": return "TikTok"
        case "instagram": return "Instagram"
        case "youtube": return "YouTube"
        default: return "其他"
        }
    }

    public var platformIcon: String {
        switch platform ?? "other" {
        case "douyin": return "music.note"
        case "kuaishou": return "bolt.fill"
        case "xiaohongshu": return "book.closed.fill"
        case "weibo": return "globe.asia.australia.fill"
        case "bilibili": return "play.rectangle.fill"
        default: return "link"
        }
    }

    public var displayTitle: String {
        if let t = title, !t.isEmpty, t != "Untitled" { return t }
        if let url = sourceUrl, !url.isEmpty { return url }
        return "未命名分析"
    }

    public var coverImageUrl: String? {
        // scrapedData is a JSONB column — pull `coverImageUrl` or `thumbnail`.
        guard let json = scrapedData?.objectValue else { return nil }
        if let v = json["coverImageUrl"], case .string(let s) = v { return s }
        if let v = json["thumbnail"], case .string(let s) = v { return s }
        return nil
    }

    public var relativeTimeString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
            ?? Date()
        return Self.relative.localizedString(for: date, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()
}

@MainActor
public final class AIAnalysisHistoryViewModel: ObservableObject {
    @Published public private(set) var items: [AIAnalysisHistoryItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingMore: Bool = false
    @Published public private(set) var hasMore: Bool = true
    @Published public var errorMessage: String? = nil

    private let pageSize = 20
    private var didInitialLoad = false

    public init() {}

    public func loadIfNeeded() async {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        await reload()
    }

    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [AIAnalysisHistoryItem] = try await supabase
                .from("ai_analysis_history")
                .select(
                    "id, platform, source_url, uploaded_image_urls, scraped_data, ai_report, ai_raw_response, status, error_message, duration_ms, model_used, cost_estimate_cents, created_at, title"
                )
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
            items = rows
            hasMore = rows.count == pageSize
            errorMessage = nil
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
        }
    }

    public func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore, !isLoading, !items.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let offset = items.count
        do {
            let rows: [AIAnalysisHistoryItem] = try await supabase
                .from("ai_analysis_history")
                .select(
                    "id, platform, source_url, uploaded_image_urls, scraped_data, ai_report, ai_raw_response, status, error_message, duration_ms, model_used, cost_estimate_cents, created_at, title"
                )
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            // Avoid dup IDs if a fresh insert lands between pages.
            let known = Set(items.map(\.id))
            items.append(contentsOf: rows.filter { !known.contains($0.id) })
            hasMore = rows.count == pageSize
        } catch {
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
        }
    }

    public func delete(_ item: AIAnalysisHistoryItem) async {
        // Optimistic remove — restore on failure.
        guard let idx = items.firstIndex(of: item) else { return }
        let snapshot = items
        items.remove(at: idx)

        do {
            try await supabase
                .from("ai_analysis_history")
                .delete()
                .eq("id", value: item.id)
                .execute()
        } catch {
            items = snapshot
            // Iter 7 §C.2 — silent CancellationError;nil 时 banner 不闪屏。
            errorMessage = ErrorPresenter.userFacingMessage(error) ?? errorMessage
        }
    }
}
