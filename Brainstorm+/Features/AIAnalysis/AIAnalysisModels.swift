import Foundation

// ══════════════════════════════════════════════════
// 1:1 port of Web `src/lib/ai/schemas/media-analysis.ts` +
// `src/app/dashboard/ai-analysis/page.tsx` local types.
// All user-visible strings are 简体中文 — match page.tsx.
// ══════════════════════════════════════════════════

public enum MediaPlatform: String, CaseIterable, Identifiable, Codable {
    case douyin
    case kuaishou
    case xiaohongshu
    case weibo
    case bilibili
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        case .weibo: return "微博"
        case .bilibili: return "B 站"
        case .other: return "其他"
        }
    }

    public var icon: String {
        switch self {
        case .douyin: return "music.note"
        case .kuaishou: return "bolt.fill"
        case .xiaohongshu: return "book.closed.fill"
        case .weibo: return "globe.asia.australia.fill"
        case .bilibili: return "play.rectangle.fill"
        case .other: return "link"
        }
    }
}

// Mirrors MediaAnalysis['basics']['platform'] enum — wider than input list
// (schema also covers tiktok / instagram / youtube).
public enum AnalysisPlatformKey: String, Codable {
    case douyin, xiaohongshu, tiktok, instagram, bilibili, weibo, kuaishou, youtube, other

    public var label: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        case .bilibili: return "B 站"
        case .weibo: return "微博"
        case .kuaishou: return "快手"
        case .youtube: return "YouTube"
        case .other: return "其他"
        }
    }
}

public struct MediaAnalysisResult: Codable {
    public let summary: String?
    public let basics: Basics
    public let metrics: Metrics
    public let content: ContentBlock
    public let evaluation: Evaluation
    public let paidPromotion: PaidPromotion
    public let keywords: Keywords
    public let otherNotes: String?

    public struct Basics: Codable {
        public let platform: AnalysisPlatformKey
        public let authorHandle: String?
        public let publishTime: String?
        public let coverTitle: String?

        enum CodingKeys: String, CodingKey {
            case platform
            case authorHandle = "author_handle"
            case publishTime = "publish_time"
            case coverTitle = "cover_title"
        }
    }

    public struct Metrics: Codable {
        public let likes: Int?
        public let collects: Int?
        public let comments: Int?
        public let shares: Int?
        public let plays: Int?
    }

    public struct ContentBlock: Codable {
        public let theme: String
        public let sellingPoints: [String]
        public let targetAudience: String

        enum CodingKeys: String, CodingKey {
            case theme
            case sellingPoints = "selling_points"
            case targetAudience = "target_audience"
        }
    }

    public struct Evaluation: Codable {
        public let strengths: [String]
        public let improvements: [String]
    }

    public struct PaidPromotion: Codable {
        public let audienceTargeting: [String]
        public let budgetTiers: BudgetTiers
        public let bestTimeSlots: [String]

        enum CodingKeys: String, CodingKey {
            case audienceTargeting = "audience_targeting"
            case budgetTiers = "budget_tiers"
            case bestTimeSlots = "best_time_slots"
        }

        public struct BudgetTiers: Codable {
            public let low: Tier
            public let medium: Tier
            public let high: Tier
        }

        public struct Tier: Codable {
            public let dailyCny: String
            public let expected: String

            enum CodingKeys: String, CodingKey {
                case dailyCny = "daily_cny"
                case expected
            }
        }
    }

    public struct Keywords: Codable {
        public let brand: [String]
        public let category: [String]
        public let longTail: [String]

        enum CodingKeys: String, CodingKey {
            case brand, category
            case longTail = "long_tail"
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary, basics, metrics, content, evaluation, keywords
        case paidPromotion = "paid_promotion"
        case otherNotes = "other_notes"
    }
}

// ── AI provider config (read from api_keys) ──
public struct AIAnalysisProvider {
    public let providerId: String
    public let providerName: String
    public let model: String
}

// ── Runtime stream/phase state ──
public enum AIAnalysisPageState: Equatable {
    case idle
    case streaming
    case done
    case error(String)
}

public enum AIAnalysisPhase: String {
    case initPhase = "INIT"
    /// Legacy generic "scraping" — kept for back-compat with old SSE feeds.
    case scraping = "SCRAPING"
    /// Iter 6 P0: short URL → final URL resolution.
    case resolvingUrl = "RESOLVING_URL"
    /// Iter 6 P0: platform-specific scraper run.
    case scrapingPage = "SCRAPING_PAGE"
    /// Iter 6 P0: cover image + interaction metric extraction.
    case extractingMedia = "EXTRACTING_MEDIA"
    /// Iter 6 P0: soft phase emitted when scrape returned empty / hit a hard
    /// error — UI shows a hint to upload a screenshot.
    case scrapeFailed = "SCRAPE_FAILED"
    case analyzing = "ANALYZING"
    case prompt    = "AI_PROMPT"
    case generating = "AI_GENERATING"
    case streaming  = "AI_STREAMING"
    case parsing    = "PARSING"
    case done = "DONE"

    public var label: String {
        switch self {
        case .initPhase: return "初始化任务"
        case .scraping: return "抓取页面内容"
        case .resolvingUrl: return "解析分享链接"
        case .scrapingPage: return "抓取页面内容"
        case .extractingMedia: return "提取封面与数据"
        case .scrapeFailed: return "抓取受限"
        case .analyzing: return "整理上下文"
        case .prompt: return "构建分析指令"
        case .generating: return "调用大模型"
        case .streaming: return "流式输出 JSON"
        case .parsing: return "解析结构化数据"
        case .done: return "完成"
        }
    }

    public var icon: String {
        switch self {
        case .initPhase: return "wand.and.stars"
        case .scraping: return "doc.text.magnifyingglass"
        case .resolvingUrl: return "link.circle"
        case .scrapingPage: return "doc.text.magnifyingglass"
        case .extractingMedia: return "photo.on.rectangle"
        case .scrapeFailed: return "exclamationmark.triangle"
        case .analyzing: return "rectangle.stack.badge.person.crop"
        case .prompt: return "text.bubble"
        case .generating: return "brain.head.profile"
        case .streaming: return "bolt.horizontal.fill"
        case .parsing: return "curlybraces"
        case .done: return "checkmark.seal.fill"
        }
    }

    /// Order shown to the user. `done` is the terminal sentinel and not rendered as a row.
    /// `scrapeFailed` is a soft event — surfaced inline rather than as a row,
    /// so it's intentionally absent from the ordered list.
    public static let ordered: [AIAnalysisPhase] = [
        .initPhase, .resolvingUrl, .scrapingPage, .extractingMedia,
        .analyzing, .prompt, .generating, .streaming, .parsing,
    ]
}

public struct AIAnalysisProgress: Equatable {
    public let phase: AIAnalysisPhase
    public let message: String
    public let percent: Int
}

/// Per-stage timing log entry (rendered in the expandable detail panel).
public struct AIAnalysisStageLog: Identifiable, Equatable {
    public let id = UUID()
    public let phase: AIAnalysisPhase
    public let message: String
    public let timestamp: Date
    /// When the stage finished. `nil` while still active.
    public var completedAt: Date?

    public var durationSeconds: Double? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(timestamp)
    }
}
