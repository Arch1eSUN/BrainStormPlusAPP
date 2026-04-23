import Foundation

// MARK: - Lightweight DTOs for 1.7 owner join + detail enrichment foundation
//
// These intentionally do NOT extend the core `Project` / `TaskModel` / `DailyLog` / `WeeklyReport`
// models. Reasons:
//
// 1. Web `fetchProjectDetail()` returns nested sub-selects with shapes that don't match the full
//    iOS app models one-to-one (Web `daily_logs.progress` / `.blockers` and `weekly_reports.summary`
//    / `.highlights` / `.challenges` aren't on the iOS `DailyLog` / `WeeklyReport` models).
// 2. Web selects date-only columns (`daily_logs.date`, `weekly_reports.week_start`) which the
//    Supabase Swift SDK's default JSON decoder (`JSONDecoder.supabase()`) does NOT decode into
//    `Date` — it only handles full ISO8601 with/without fractional seconds. Modeling those
//    fields as `String` here avoids a decoder failure silently wiping real data.
// 3. These are read-only foundation views. Using dedicated DTOs keeps the Project/Task/etc. core
//    models stable while we iterate on detail parity.
//
// Source of truth: `BrainStorm+-Web/src/lib/actions/projects.ts` → `fetchProjectDetail()`.

/// Nested `profiles:owner_id(full_name, avatar_url)` join result from Web projects query.
///
/// iOS fetches this separately (not as a nested join) because the core `Project` model's
/// `CodingKeys` don't describe the nested shape. We look it up by `owner_id` against `profiles`.
public struct ProjectOwnerSummary: Identifiable, Codable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
    }
}

/// Minimal task row returned by Web `adminDb.from('tasks').select('id, title, status, priority, assignee_id, ...')`.
///
/// Kept intentionally small — this is for the "tasks attached to this project" compact detail
/// section, not the full tasks module. Status / priority are `String` (not the iOS `TaskStatus` /
/// `TaskPriority` enums) so an unknown value returned by the server doesn't crash detail decode.
public struct ProjectTaskSummary: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let status: String
    public let priority: String
    public let assigneeId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case priority
        case assigneeId = "assignee_id"
    }
}

/// Minimal `daily_logs` row scoped by `project_id`.
///
/// `date` is a Postgres `date` column (YYYY-MM-DD). The Supabase Swift SDK default decoder doesn't
/// parse date-only strings into `Date`, so this keeps it as `String` for safe decode + display.
///
/// 1.8: added `userId` so we can batch-hydrate `profiles:user_id(full_name)` in one
/// `profiles.in("id", values: ...)` call (see `ProjectDetailViewModel.hydrateSublistProfiles()`).
public struct ProjectDailyLogSummary: Identifiable, Codable, Hashable {
    public let id: UUID
    public let date: String
    public let content: String
    public let progress: String?
    public let blockers: String?
    public let userId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case content
        case progress
        case blockers
        case userId = "user_id"
    }
}

/// Minimal `weekly_reports` row matched by `project_ids @> [projectId]`.
///
/// Web uses:
/// ```ts
/// adminDb.from('weekly_reports')
///   .select('id, week_start, summary, highlights, challenges, ...')
///   .contains('project_ids', [projectId])
///   .order('week_start', { ascending: false })
///   .limit(5)
/// ```
public struct ProjectWeeklySummary: Identifiable, Codable, Hashable {
    public let id: UUID
    public let weekStart: String
    public let summary: String
    public let highlights: String?
    public let challenges: String?
    public let userId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case summary
        case highlights
        case challenges
        case userId = "user_id"
    }
}

// MARK: - 2.2 Project AI Summary (Web bridge)

/// Structured result of `ProjectDetailViewModel.generateSummary()`.
///
/// Phase 6.1: the 2.2 local-synthesis foundation has been replaced with a direct HTTP call
/// to the Web bridge at `POST /api/ai/project-summary`. The Web route fans out the same
/// parallel Supabase reads (tasks(30) + daily_logs(10) + weekly_reports(3)), calls
/// `askAI({ scenario: 'project_summary' })` server-side with org-resolved provider
/// credentials, and persists the result in `project_summaries`. iOS now consumes the
/// LLM-generated structured JSON directly.
///
/// Wire shape (snake_case — mirrored exactly via `CodingKeys` so the iOS model keeps the
/// conventional Swift camelCase while decoding the Web response 1:1):
/// ```json
/// {
///   "snapshot_summary":      "<multi-paragraph narrative>",
///   "completed_highlights":  ["...", "..."],
///   "in_progress":           ["...", "..."],
///   "next_steps":            ["...", "..."],
///   "risk_notes":            ["...", "..."],
///   "generated_at":          "<ISO-8601>",
///   "model_used":            "<primary or fallback model name>",
///   "scenario":              "project_summary"
/// }
/// ```
public struct ProjectSummary: Equatable, Decodable {
    public let snapshotSummary: String
    public let completedHighlights: [String]
    public let inProgress: [String]
    public let nextSteps: [String]
    public let riskNotes: [String]
    public let generatedAt: String?
    public let modelUsed: String?
    public let scenario: String?

    enum CodingKeys: String, CodingKey {
        case snapshotSummary = "snapshot_summary"
        case completedHighlights = "completed_highlights"
        case inProgress = "in_progress"
        case nextSteps = "next_steps"
        case riskNotes = "risk_notes"
        case generatedAt = "generated_at"
        case modelUsed = "model_used"
        case scenario
    }

    public init(
        snapshotSummary: String,
        completedHighlights: [String] = [],
        inProgress: [String] = [],
        nextSteps: [String] = [],
        riskNotes: [String] = [],
        generatedAt: String? = nil,
        modelUsed: String? = nil,
        scenario: String? = nil
    ) {
        self.snapshotSummary = snapshotSummary
        self.completedHighlights = completedHighlights
        self.inProgress = inProgress
        self.nextSteps = nextSteps
        self.riskNotes = riskNotes
        self.generatedAt = generatedAt
        self.modelUsed = modelUsed
        self.scenario = scenario
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.snapshotSummary = (try? c.decode(String.self, forKey: .snapshotSummary)) ?? ""
        self.completedHighlights = (try? c.decode([String].self, forKey: .completedHighlights)) ?? []
        self.inProgress = (try? c.decode([String].self, forKey: .inProgress)) ?? []
        self.nextSteps = (try? c.decode([String].self, forKey: .nextSteps)) ?? []
        self.riskNotes = (try? c.decode([String].self, forKey: .riskNotes)) ?? []
        self.generatedAt = try? c.decode(String.self, forKey: .generatedAt)
        self.modelUsed = try? c.decode(String.self, forKey: .modelUsed)
        self.scenario = try? c.decode(String.self, forKey: .scenario)
    }
}

// MARK: - 2.3 Project Risk Analysis Foundation

/// Read-only snapshot of the most recent `project_risk_summaries` row for this project.
///
/// **Web source-of-truth discrepancy (2.3)**: Web's `generateProjectRiskAnalysis(projectId, { forceRegenerate })`
/// in `BrainStorm+-Web/src/lib/actions/summary-actions.ts` is a `'use server'` action, NOT
/// an HTTP API route. It fans out parallel Supabase reads (project + tasks(50) + daily_logs(10)),
/// calls `askAI({ scenario: 'project_risk_analysis' })` with org provider credentials decrypted
/// server-side via `decryptApiKey()`, parses the risk level from the LLM's first line, and
/// upserts the result into the `project_risk_summaries` table (keyed by `project_id`).
/// Native iOS cannot invoke that server action and must not embed decrypted provider keys on-device.
///
/// **Key difference vs 2.2**: Unlike the ephemeral `generateProjectSummary` flow (which is not
/// persisted on Web, so iOS 2.2 had to substitute a deterministic local synthesis), risk analysis
/// DOES persist in `project_risk_summaries`. iOS 2.3 therefore ships a faithful read-only
/// foundation: read the cached row directly via Supabase and display it with provenance
/// (generated_at + model_used). Generating NEW analyses from iOS is deferred until a server-side
/// `/api/ai/project-risk` endpoint (or Supabase Edge Function) exposes the flow to native callers.
///
/// Shape choices:
/// - `summary` is the raw text stored by the Web server action.
/// - `riskLevel` normalizes the stored string to a stable enum; unknown / null values map to
///   `.unknown` so foundation decode never fails on values outside the Web-defined set.
/// - `generatedAt`, `model`, `scenario` mirror Web's `AIResultMeta` so UI can show provenance.
public struct ProjectRiskAnalysis: Equatable {
    public let summary: String
    public let riskLevel: RiskLevel
    public let risks: [RiskItem]
    public let generatedAt: Date?
    public let model: String?
    public let scenario: String?

    public enum RiskLevel: String, Equatable {
        case low
        case medium
        case high
        case critical
        case unknown
    }

    public init(
        summary: String,
        riskLevel: RiskLevel,
        risks: [RiskItem] = [],
        generatedAt: Date? = nil,
        model: String? = nil,
        scenario: String? = nil
    ) {
        self.summary = summary
        self.riskLevel = riskLevel
        self.risks = risks
        self.generatedAt = generatedAt
        self.model = model
        self.scenario = scenario
    }

    /// One structured risk row from the Web `/api/ai/project-risk` response.
    ///
    /// Wire shape (snake_case → camelCase via `CodingKeys`):
    /// ```json
    /// { "category": "schedule|progress|resource|blocker|other",
    ///   "severity": "low|medium|high|critical",
    ///   "title": "...",
    ///   "description": "...",
    ///   "suggested_action": "..." }
    /// ```
    public struct RiskItem: Equatable, Hashable, Decodable, Identifiable {
        public var id: String { "\(category)-\(severity)-\(title)" }
        public let category: String
        public let severity: String
        public let title: String
        public let description: String
        public let suggestedAction: String

        enum CodingKeys: String, CodingKey {
            case category
            case severity
            case title
            case description
            case suggestedAction = "suggested_action"
        }

        public init(
            category: String,
            severity: String,
            title: String,
            description: String,
            suggestedAction: String
        ) {
            self.category = category
            self.severity = severity
            self.title = title
            self.description = description
            self.suggestedAction = suggestedAction
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.category = (try? c.decode(String.self, forKey: .category)) ?? "other"
            self.severity = (try? c.decode(String.self, forKey: .severity)) ?? "low"
            self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
            self.description = (try? c.decode(String.self, forKey: .description)) ?? ""
            self.suggestedAction = (try? c.decode(String.self, forKey: .suggestedAction)) ?? ""
        }
    }
}

/// Raw decode shape for `POST /api/ai/project-risk` response. Kept separate from
/// `ProjectRiskAnalysis` because the Web response uses string risk levels + ISO 8601
/// timestamps, whereas the public model exposes a normalized `RiskLevel` enum + `Date?`.
/// The VM converts `ProjectRiskAnalysisResponse → ProjectRiskAnalysis` before publishing.
public struct ProjectRiskAnalysisResponse: Decodable {
    public let summary: String
    public let riskLevel: String?
    public let overallRiskLevel: String?
    public let risks: [ProjectRiskAnalysis.RiskItem]
    public let generatedAt: String?
    public let modelUsed: String?
    public let scenario: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case riskLevel = "risk_level"
        case overallRiskLevel = "overall_risk_level"
        case risks
        case generatedAt = "generated_at"
        case modelUsed = "model_used"
        case scenario
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.riskLevel = try? c.decode(String.self, forKey: .riskLevel)
        self.overallRiskLevel = try? c.decode(String.self, forKey: .overallRiskLevel)
        self.risks = (try? c.decode([ProjectRiskAnalysis.RiskItem].self, forKey: .risks)) ?? []
        self.generatedAt = try? c.decode(String.self, forKey: .generatedAt)
        self.modelUsed = try? c.decode(String.self, forKey: .modelUsed)
        self.scenario = try? c.decode(String.self, forKey: .scenario)
    }
}

// MARK: - 2.4 Linked Risk Actions Foundation

/// Read-only row from `risk_actions`, scoped to rows where
/// `ai_source_id = project_risk_summaries.id` for the currently displayed project.
///
/// **Web source-of-truth (2.4)**: Web's `getLinkedRiskActions(projectId)` in
/// `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (lines 597-626) does a two-step read:
///
/// 1. `project_risk_summaries.select('id').eq('project_id', projectId).maybeSingle()` —
///    locate the risk summary id for this project.
/// 2. `risk_actions.select('id, title, status, severity, ai_source_id')
///      .eq('ai_source_id', summary.id)
///      .order('created_at', { ascending: false })
///      .limit(20)`.
///
/// Web surface (`BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 705-724) renders
/// only the first three rows and a total-count badge; the "转为风险动作" button that converts a
/// risk_item into a risk_action is Web-only (it writes via `syncRiskFromDetection`).
///
/// Shape choices:
/// - `id`, `title`, `status`, `severity`, `aiSourceId` match Web's select projection exactly.
/// - `status` / `severity` decoded as `String` (not typed enums) so unexpected server values
///   don't crash decode — the Web-defined vocabularies are `status ∈ {open, acknowledged,
///   in_progress, resolved, dismissed}` and `severity ∈ {low, medium, high}` (per migration
///   `037_round8_risk_knowledge_ai.sql`), but iOS renders styling via a defensive switch that
///   falls back to a neutral look on unknown values.
/// - `aiSourceId` preserved so UI can verify linkage visibly if needed; not currently displayed.
public struct ProjectLinkedRiskAction: Identifiable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let status: String
    public let severity: String
    public let aiSourceId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case severity
        case aiSourceId = "ai_source_id"
    }
}

// MARK: - 2.5 Resolution Feedback Foundation

/// Aggregated read-only resolution feedback snapshot for a project, matching the shape Web's
/// `getProjectRiskResolutionSummary(projectId)` server action returns.
///
/// **Web source-of-truth (2.5)**: `BrainStorm+-Web/src/lib/actions/summary-actions.ts` lines
/// 630-714 define a two-step read:
///
/// 1. `project_risk_summaries.select('id').eq('project_id', projectId).maybeSingle()` — the same
///    anchor lookup used by 2.3 / 2.4. No anchor → `{ data: null, error: null }` (NOT an error).
/// 2. `risk_actions.select('title, status, severity, resolution_category, effectiveness,
///      follow_up_required, reopen_count, resolved_at')
///      .eq('ai_source_id', summary.id)
///      .order('resolved_at', { ascending: false, nullsFirst: false })
///      .limit(50)`
///
/// All aggregation happens client-side over the limit-50 result — `total` therefore caps at 50,
/// matching Web's behavior exactly (not a bug, not a source-of-truth divergence).
///
/// **No server-only secrets**: unlike 2.2 / 2.3, this flow makes no `askAI()` call and does NOT
/// depend on `decryptApiKey()` / `api_keys`. iOS replicates both steps via direct PostgREST under
/// the same org-scoped RLS that gates all other risk reads.
///
/// Web dashboard render (`BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 725-838):
/// - Count badges: resolved / dismissed / active / followUpRequired / reopenedCount.
/// - Predictive "易重开" badge when `reopenedCount > 0 && active > 0`.
/// - Governance badge: "干预已生效" when any recent resolution has
///   `effectiveness == 'effective' && category == 'root_cause_fixed'`; "待治理干预" when
///   `reopenedCount > 0 && active > 0` (same trigger as 易重开). iOS mirrors this derivation
///   via `governanceSignal` below — it is a computed property over the raw fields, NOT an
///   additional server read.
/// - `dominantCategory` labeled via a small `category → 中文 label` map. iOS substitutes an
///   English humanize fallback (`root_cause_fixed` → `Root cause fixed`) since 2.5 ships
///   English-only copy (i18n is carry-forward debt).
/// - `recentResolutions` top-3 rendered as a compact table. iOS mirrors top-3 render cap.
///
/// **Shape choices**:
/// - `recentResolutions` decoded as a plain array of `RecentResolution` (not keyed by id) —
///   mirrors Web's inline anonymous type. No stable id is surfaced by Web for these rows.
/// - `dominantCategory` / `effectiveness` / `status` / `severity` decoded as `String` so future
///   server vocabulary expansion degrades gracefully.
/// - `resolvedAt` decoded as `String` — Postgres `timestamptz` comes back as ISO 8601, and the
///   Swift SDK default decoder only handles full ISO 8601 with fractional seconds. Keeping it
///   as `String` avoids a decode crash on values like `2026-04-16T12:34:56+00:00`; the VM
///   parses via `parseTimestamp(_:)` on render (same pattern as 2.3 `generated_at`).
public struct ProjectResolutionFeedback: Equatable {
    public let total: Int
    public let resolved: Int
    public let dismissed: Int
    public let active: Int
    public let followUpRequired: Int
    public let dominantCategory: String?
    public let reopenedCount: Int
    public let recentResolutions: [RecentResolution]

    public struct RecentResolution: Equatable, Hashable {
        public let title: String
        public let status: String
        public let category: String?
        public let effectiveness: String?
        /// Raw ISO 8601 `timestamptz` string as returned by PostgREST. `nil` when the column
        /// was `NULL` on the server. UI layer parses via `parseTimestamp(_:)` on render so a
        /// malformed timestamp hides the date column rather than crashing decode.
        public let resolvedAtRaw: String?
    }

    /// Derived governance signal (mirrors Web's governance intervention status at
    /// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 780-796).
    ///
    /// - `.interventionEffective`: at least one recent resolution has
    ///   `effectiveness == "effective"` AND `category == "root_cause_fixed"`. Web badge
    ///   copy: "干预已生效" (green tone).
    /// - `.needsIntervention`: `reopenedCount > 0 && active > 0`. Web badge copy: "待治理干预".
    /// - `.none`: neither signal applies. No badge rendered on Web; iOS likewise hides.
    ///
    /// **Priority when both conditions hold**: Web uses **effective-first** priority —
    /// `hasEffective` short-circuits before `needsIntervention` is ever checked. iOS mirrors
    /// this exactly. The predictive "易重开" indicator (`isProneToReopen`) is a *separate*
    /// rail and continues to render independently regardless of which governance signal
    /// fires; see `isProneToReopen` below.
    public enum GovernanceSignal: Equatable {
        case none
        case interventionEffective
        case needsIntervention
    }

    public var governanceSignal: GovernanceSignal {
        let effective = recentResolutions.contains { resolution in
            resolution.effectiveness == "effective" && resolution.category == "root_cause_fixed"
        }
        if effective { return .interventionEffective }
        let needs = reopenedCount > 0 && active > 0
        return needs ? .needsIntervention : .none
    }

    /// Predictive "易重开" (prone-to-reopen) indicator — mirrors Web's pulsing rose badge at
    /// lines 754-758. Trigger: `reopenedCount > 0 && active > 0`. This is an **independent
    /// rail** from `governanceSignal`: it fires whenever the trigger holds, even when
    /// `governanceSignal == .interventionEffective` (i.e. some interventions have worked
    /// while new reopens are still accumulating). Do not conflate its semantic with the
    /// governance intervention status.
    public var isProneToReopen: Bool {
        reopenedCount > 0 && active > 0
    }
}

// MARK: - 2.6 Risk Action Sync Write Path Foundation

/// Confirmation-preview payload for the 2.6 "Convert to risk action" write path. Built by
/// `ProjectDetailViewModel.riskActionSyncDraft()` immediately before the user sees the
/// confirmation dialog and rebuilt server-side during the actual insert — the view never
/// mutates this and the VM never persists it. Mirrors the three user-visible inputs Web's
/// `handleSyncToRiskAction` passes into `syncRiskFromDetection` at
/// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 687-697:
///
/// ```tsx
/// syncRiskFromDetection({
///   type: 'manual',
///   title: `[${detail.name}] 风险项`,
///   detail: riskSummary.slice(0, 200),
///   severity: riskLevel === 'critical' || riskLevel === 'high'
///     ? 'high' : riskLevel === 'medium' ? 'medium' : 'low',
///   ...
/// })
/// ```
///
/// `severity` is pre-mapped from `ProjectRiskAnalysis.RiskLevel` (critical/high → `"high"`,
/// medium → `"medium"`, low → `"low"`, unknown → `"medium"`) so the view just renders a
/// capsule without re-running the mapping.
///
/// **Persistence parity note**: `title` deliberately carries the literal Chinese suffix
/// `风险项` so rows persisted from iOS match Web exactly in the `risk_actions.title`
/// column — otherwise a Web operator would see a mixed-locale list of actions keyed by
/// origin-of-write rather than by risk content. iOS UI copy stays English everywhere
/// else; this is a persistence-level literal, not a user-facing one.
public struct RiskActionSyncDraft: Equatable {
    public let title: String
    public let detail: String
    public let severity: String
}
