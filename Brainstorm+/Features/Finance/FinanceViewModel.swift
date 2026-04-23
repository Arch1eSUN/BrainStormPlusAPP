import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════
// BrainStorm+ iOS — Finance AI Workspace ViewModel
//
// 1:1 port of Web `src/app/dashboard/finance/page.tsx` (770 行)
// 对应 Web 三条工作链：文档整理 / 报表整理 / 数据处理
// 数据来源：public.ai_work_records (workbench='finance')
// 详见迁移 021_ai_work_records.sql
//
// 本 ViewModel 负责：读取当前用户的历史处理记录 + 解码结构化输出 +
// submitAIProcess() 通过 POST /api/mobile/finance/ai-process 提交新请求
// （Phase 5.3 接入）。
// ══════════════════════════════════════════════════

// MARK: - Chain Enum

public enum FinanceChain: String, Codable, CaseIterable, Identifiable {
    case documentOrganize = "document_organize"
    case reportSummarize = "report_summarize"
    case dataProcess = "data_process"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .documentOrganize: return "文档整理"
        case .reportSummarize: return "报表整理"
        case .dataProcess: return "数据处理"
        }
    }

    public var shortLabel: String {
        switch self {
        case .documentOrganize: return "AI 文档整理"
        case .reportSummarize: return "AI 报表整理"
        case .dataProcess: return "AI 数据处理"
        }
    }

    public var description: String {
        switch self {
        case .documentOrganize: return "发票、合同、报销单等财务文档的结构化整理"
        case .reportSummarize: return "财务报表深度分析、指标提取与趋势洞察"
        case .dataProcess: return "财务数据分类、提取与校验"
        }
    }

    public var iconName: String {
        switch self {
        case .documentOrganize: return "doc.text"
        case .reportSummarize: return "chart.bar.xaxis"
        case .dataProcess: return "tray.2"
        }
    }

    /// Web 路由 payload 里用的简短 key：document / report / data
    public var payloadKey: String {
        switch self {
        case .documentOrganize: return "document"
        case .reportSummarize: return "report"
        case .dataProcess: return "data"
        }
    }
}

// ── Dropdown enums（对齐 Web finance/page.tsx 的 select 选项）──────

public enum FinanceDocType: String, CaseIterable, Identifiable, Codable {
    case invoice
    case contract
    case reimbursement
    case statement
    case other

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .invoice: return "发票"
        case .contract: return "合同"
        case .reimbursement: return "报销单"
        case .statement: return "账单/流水"
        case .other: return "其他文档"
        }
    }
}

public enum FinanceReportType: String, CaseIterable, Identifiable, Codable {
    case monthly
    case quarterly
    case annual
    case adhoc

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .monthly: return "月度报表"
        case .quarterly: return "季度报表"
        case .annual: return "年度报表"
        case .adhoc: return "专项报表"
        }
    }
}

public enum FinanceProcessType: String, CaseIterable, Identifiable, Codable {
    case classification
    case extraction
    case validation

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .classification: return "分类标注"
        case .extraction: return "关键字段提取"
        case .validation: return "数据校验"
        }
    }
}

// MARK: - Row Model (ai_work_records)

public struct FinanceAIRecord: Codable, Identifiable, Hashable {
    public let id: UUID
    public let chain: String
    public let inputSummary: String?
    public let outputJson: AnyCodable?
    public let aiModel: String?
    public let status: String
    public let createdAt: Date

    public init(
        id: UUID,
        chain: String,
        inputSummary: String?,
        outputJson: AnyCodable?,
        aiModel: String?,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.chain = chain
        self.inputSummary = inputSummary
        self.outputJson = outputJson
        self.aiModel = aiModel
        self.status = status
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chain
        case inputSummary = "input_summary"
        case outputJson = "output_json"
        case aiModel = "ai_model"
        case status
        case createdAt = "created_at"
    }

    public var chainEnum: FinanceChain? {
        FinanceChain(rawValue: chain)
    }

    /// Parsed, structured view of `output_json`. Returns nil if payload is
    /// malformed or empty. Web page.tsx:524 unfolds exactly these keys.
    public var parsedOutput: FinanceParsedOutput? {
        guard let json = outputJson?.value as? [String: Any] else { return nil }
        return FinanceParsedOutput(json: json)
    }
}

// MARK: - Parsed Output (mirrors Web out.* shape)

public struct FinanceParsedOutput: Hashable {
    public let summary: String?
    public let keyMetrics: [KeyMetric]
    public let financialItems: [FinancialItem]
    public let records: [DataRecord]
    public let highlights: [String]
    public let concerns: [String]
    public let riskFlags: [String]
    public let actionItems: [String]
    public let recommendations: [String]
    public let suggestedNextSteps: [String]
    public let rawText: String?

    public struct KeyMetric: Hashable, Identifiable {
        public let id = UUID()
        public let name: String
        public let value: String
        public let trend: String?    // "up" / "down" / "flat"
        public let note: String?
    }

    public struct FinancialItem: Hashable, Identifiable {
        public let id = UUID()
        public let description: String
        public let amount: String
        public let category: String
    }

    public struct DataRecord: Hashable, Identifiable {
        public let id = UUID()
        public let index: Int
        public let original: String
        public let result: String
        public let confidence: Int
        public let notes: String?
    }

    init(json: [String: Any]) {
        self.summary = json["summary"] as? String
        self.rawText = json["raw_text"] as? String

        if let arr = json["key_metrics"] as? [[String: Any]] {
            self.keyMetrics = arr.map {
                KeyMetric(
                    name: ($0["name"] as? String) ?? "",
                    value: ($0["value"] as? String) ?? "",
                    trend: $0["trend"] as? String,
                    note: $0["note"] as? String
                )
            }
        } else {
            self.keyMetrics = []
        }

        if let arr = json["financial_items"] as? [[String: Any]] {
            self.financialItems = arr.map {
                FinancialItem(
                    description: ($0["description"] as? String) ?? "",
                    amount: ($0["amount"] as? String) ?? "",
                    category: ($0["category"] as? String) ?? ""
                )
            }
        } else {
            self.financialItems = []
        }

        if let arr = json["records"] as? [[String: Any]] {
            self.records = arr.enumerated().map { (idx, r) in
                DataRecord(
                    index: (r["index"] as? Int) ?? idx + 1,
                    original: (r["original"] as? String) ?? "",
                    result: (r["result"] as? String) ?? "",
                    confidence: (r["confidence"] as? Int) ?? 0,
                    notes: r["notes"] as? String
                )
            }
        } else {
            self.records = []
        }

        func strArr(_ key: String) -> [String] {
            (json[key] as? [String]) ?? []
        }
        self.highlights = strArr("highlights")
        self.concerns = strArr("concerns")
        self.riskFlags = strArr("risk_flags")
        self.actionItems = strArr("action_items")
        self.recommendations = strArr("recommendations")
        self.suggestedNextSteps = strArr("suggested_next_steps")
    }

    public var hasAnyContent: Bool {
        summary != nil || !keyMetrics.isEmpty || !financialItems.isEmpty
        || !records.isEmpty || !highlights.isEmpty || !concerns.isEmpty
        || !riskFlags.isEmpty || !actionItems.isEmpty || !recommendations.isEmpty
        || !suggestedNextSteps.isEmpty || rawText != nil
    }
}

// MARK: - AnyCodable helper

public struct AnyCodable: Codable, Hashable {
    public let value: Any?

    public init(_ value: Any?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = nil; return }
        if let b = try? c.decode(Bool.self) { self.value = b; return }
        if let i = try? c.decode(Int.self) { self.value = i; return }
        if let d = try? c.decode(Double.self) { self.value = d; return }
        if let s = try? c.decode(String.self) { self.value = s; return }
        if let a = try? c.decode([AnyCodable].self) {
            self.value = a.map { $0.value as Any }; return
        }
        if let obj = try? c.decode([String: AnyCodable].self) {
            var dict: [String: Any] = [:]
            for (k, v) in obj { dict[k] = v.value as Any }
            self.value = dict; return
        }
        self.value = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        guard let v = value else { try c.encodeNil(); return }
        switch v {
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let arr as [Any]:
            try c.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            var mapped: [String: AnyCodable] = [:]
            for (k, val) in dict { mapped[k] = AnyCodable(val) }
            try c.encode(mapped)
        default:
            try c.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value as Any) == String(describing: rhs.value as Any)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value as Any))
    }
}

// MARK: - ViewModel

@MainActor
public final class FinanceViewModel: ObservableObject {
    @Published public var records: [FinanceAIRecord] = []
    @Published public var selectedChain: FinanceChain = .documentOrganize
    @Published public var selectedRecord: FinanceAIRecord?
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    // ── AI 处理输入态（对齐 Web `finance/page.tsx` 的三个 chain 的输入+下拉）
    @Published public var inputText: String = ""
    @Published public var docType: FinanceDocType = .invoice
    @Published public var reportType: FinanceReportType = .monthly
    @Published public var processType: FinanceProcessType = .classification
    @Published public var isSubmitting: Bool = false

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ── Submit bridge（已接入 POST /api/mobile/finance/ai-process）────
    // TODO(finance-ai-orchestrator-bridge): 已接入，由 Web 路由代理 askAI
    // orchestrator；iOS 侧只透传 chain + 输入 + 下拉选择。
    public func submitAIProcess() async -> FinanceAIRecord? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请先填写待处理的文本内容"
            return nil
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let session = try await client.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/finance/ai-process")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 90

            var payload: [String: Any] = [
                "chain": selectedChain.payloadKey,
                "input_text": trimmed,
            ]
            switch selectedChain {
            case .documentOrganize:
                payload["doc_type"] = docType.rawValue
            case .reportSummarize:
                payload["report_type"] = reportType.rawValue
            case .dataProcess:
                payload["process_type"] = processType.rawValue
            }
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
                errorMessage = "AI 处理失败：\(msg)"
                return nil
            }

            // 兼容两种返回：直接字段 `record_id` + `parsed`，或嵌套 `record`。
            let recordId: String? = (json?["record_id"] as? String)
                ?? (json?["id"] as? String)
            let parsedObj = (json?["parsed"] as? [String: Any])
                ?? (json?["output"] as? [String: Any])
                ?? (json?["output_json"] as? [String: Any])
            let inputSummary = (json?["input_summary"] as? String)
                ?? String(trimmed.prefix(80))
            let aiModel = json?["ai_model"] as? String
            let status = (json?["status"] as? String) ?? "completed"

            guard let idStr = recordId, let uuid = UUID(uuidString: idStr) else {
                errorMessage = "AI 处理返回缺少 record_id"
                return nil
            }

            let record = FinanceAIRecord(
                id: uuid,
                // 本地持久化用 rawValue，让 chainEnum 能解出来；Web 路由 payload
                // 侧的 short key 由 payloadKey 提供，仅在请求体里用。
                chain: selectedChain.rawValue,
                inputSummary: inputSummary,
                outputJson: parsedObj.map { AnyCodable($0) },
                aiModel: aiModel,
                status: status,
                createdAt: Date()
            )
            // 前置到历史列表，便于列表立刻反映
            records.insert(record, at: 0)
            inputText = ""
            return record
        } catch {
            errorMessage = "AI 处理失败：\(ErrorLocalizer.localize(error))"
            return nil
        }
    }

    /// Fetch the current user's finance AI history. Mirrors Web
    /// `fetchFinanceAIHistory()` (finance-ai.ts:260).
    public func fetchHistory(limit: Int = 20) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [FinanceAIRecord] = try await client
                .from("ai_work_records")
                .select("id, chain, input_summary, output_json, ai_model, status, created_at")
                .eq("workbench", value: "finance")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            self.records = rows
        } catch {
            self.errorMessage = "历史记录加载失败：\(ErrorLocalizer.localize(error))"
        }
    }

    /// Records filtered by the chain pill selected in the header.
    public var filteredRecords: [FinanceAIRecord] {
        records.filter { $0.chainEnum == selectedChain }
    }

    /// Aggregate confidence distribution across the last N data-process
    /// records — fuels the Charts bar in `FinanceView`.
    public var confidenceBuckets: [ConfidenceBucket] {
        let allRecords = records
            .filter { $0.chainEnum == .dataProcess }
            .flatMap { $0.parsedOutput?.records ?? [] }
        guard !allRecords.isEmpty else { return [] }

        var high = 0, medium = 0, low = 0
        for r in allRecords {
            if r.confidence >= 80 { high += 1 }
            else if r.confidence >= 60 { medium += 1 }
            else { low += 1 }
        }
        return [
            ConfidenceBucket(label: "高 (≥80)", count: high),
            ConfidenceBucket(label: "中 (60–79)", count: medium),
            ConfidenceBucket(label: "低 (<60)", count: low),
        ]
    }

    /// Metric frequency across all report_summarize records — fuels the
    /// "关键指标分布" chart. Returns top-N metric names and how often each
    /// appears in history.
    public var metricFrequency: [MetricCount] {
        let metrics = records
            .filter { $0.chainEnum == .reportSummarize }
            .flatMap { $0.parsedOutput?.keyMetrics ?? [] }
        var freq: [String: Int] = [:]
        for m in metrics where !m.name.isEmpty {
            freq[m.name, default: 0] += 1
        }
        return freq
            .map { MetricCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { $0 }
    }

    public struct ConfidenceBucket: Hashable, Identifiable {
        public var id: String { label }
        public let label: String
        public let count: Int
    }

    public struct MetricCount: Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let count: Int
    }
}
