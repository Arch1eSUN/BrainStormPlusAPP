import Foundation
import Combine
import Supabase

@MainActor
public class ProjectDetailViewModel: ObservableObject {
    /// The project currently displayed. Seeded from the list row so the detail view has something to
    /// render immediately, then replaced when the fresh `fetchDetail()` call completes.
    ///
    /// On `.denied`, the seed is cleared so UI cannot silently render the tapped row through a gate failure.
    @Published public var project: Project?
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    // MARK: - 1.7 owner + detail enrichment state

    /// Result of the owner profile join (`profiles:owner_id(full_name, avatar_url)` on Web).
    ///
    /// iOS fetches this separately rather than as a nested select because the core `Project` model's
    /// `CodingKeys` don't describe the nested shape. `nil` means: not yet fetched, owner missing on the
    /// project, or owner fetch failed (see `enrichmentErrors[.owner]`).
    @Published public var owner: ProjectOwnerSummary?

    /// Up to 50 most recent tasks attached to this project, ordered by `created_at DESC`.
    /// Empty array may mean: no tasks, or a fetch failure recorded in `enrichmentErrors[.tasks]`.
    @Published public var tasks: [ProjectTaskSummary] = []

    /// Up to 10 most recent `daily_logs` rows for this project, ordered by `date DESC`.
    @Published public var dailyLogs: [ProjectDailyLogSummary] = []

    /// Up to 5 most recent `weekly_reports` rows where `project_ids @> [projectId]`, ordered by
    /// `week_start DESC`.
    @Published public var weeklySummaries: [ProjectWeeklySummary] = []

    /// Per-section enrichment error state. Kept separate from `errorMessage` (which is the
    /// first-load / gate / project-row failure surface) so one failing sub-query doesn't knock out
    /// the rest of the detail view.
    ///
    /// 1.8 adds `.sublistProfiles` for the batched `profiles.in("id", values: ...)` hydration that
    /// resolves tasks `assignee_id` and daily/weekly `user_id` into human-readable names. If that
    /// single batched call fails, the rows still render with UUID fallback.
    public enum EnrichmentSection: Hashable {
        case owner
        case tasks
        case dailyLogs
        case weeklySummaries
        case sublistProfiles
    }
    @Published public var enrichmentErrors: [EnrichmentSection: String] = [:]

    /// 1.8: profiles keyed by UUID for task assignees + daily-log authors + weekly-report authors.
    ///
    /// Mirrors Web detail parity for nested `profiles:assignee_id(full_name)` / `profiles:user_id(full_name)`
    /// sub-selects inside `fetchProjectDetail()`:
    ///
    /// ```ts
    /// adminDb.from('tasks')
    ///   .select('id, title, status, priority, assignee_id, profiles:assignee_id(full_name)')
    /// adminDb.from('daily_logs')
    ///   .select('id, date, content, progress, blockers, profiles:user_id(full_name)')
    /// adminDb.from('weekly_reports')
    ///   .select('id, week_start, summary, highlights, challenges, profiles:user_id(full_name)')
    /// ```
    ///
    /// Instead of forcing nested-join decode on each sub-query (which the Swift SDK handles awkwardly
    /// with flat `Codable` DTOs), we run ONE batched `profiles.in("id", values: allIds)` query after
    /// the section fetches resolve. This is not N+1 — it's a single follow-up query.
    ///
    /// `profilesById` deliberately reuses `ProjectOwnerSummary` because the select shape is the same
    /// (`id, full_name, avatar_url`); 1.8 views only consume `fullName` from this map. Denied path
    /// clears this dictionary via `applyDeniedState()`.
    @Published public var profilesById: [UUID: ProjectOwnerSummary] = [:]

    /// True while the enrichment parallel-fetch is in flight (distinct from `isLoading`, which
    /// covers the access gate + `projects` row fetch).
    @Published public var isLoadingEnrichment: Bool = false

    /// 2.0: true while a project delete is in flight. Used by the toolbar and confirmation
    /// dialog to disable destructive inputs and render a progress overlay. Distinct from
    /// `isLoading` (access gate + row refresh) and `isLoadingEnrichment` (sub-sections).
    @Published public var isDeleting: Bool = false

    /// 2.0: isolated delete-failure surface. Kept separate from `errorMessage` (first-load
    /// / gate / row failure) and from `enrichmentErrors` (per-section read failures) so a
    /// failed destructive action does not wipe unrelated read-only state.
    @Published public var deleteErrorMessage: String? = nil

    // MARK: - 2.2 / Phase 6.1 AI summary state (Web bridge)

    /// Phase 6.1: resolved structured summary from the most recent `generateSummary()` call
    /// against the Web bridge `POST /api/ai/project-summary`. `nil` when no summary has been
    /// generated yet (idle) OR when the most recent attempt failed (see `summaryErrorMessage`).
    ///
    /// The backing type now mirrors the Web JSON response 1:1 (snapshot_summary +
    /// completed_highlights + in_progress + next_steps + risk_notes + provenance). The
    /// previous 2.2 local-synthesis `ProjectSummaryFoundation` has been retired — see
    /// the `// 已切换到 Web bridge /api/ai/project-summary` comments in this file.
    @Published public var projectSummary: ProjectSummary? = nil

    /// Phase 6.1: true while `generateSummary()` is awaiting the Web bridge response.
    /// Drives the "生成中…" button state in the UI. Distinct from `isLoading`
    /// (first-load / gate / row refresh), `isLoadingEnrichment` (per-section sub-fetches),
    /// and `isDeleting` (destructive action).
    @Published public var isGeneratingSummary: Bool = false

    /// 2.2: isolated error surface for the AI summary foundation. Kept separate from
    /// `errorMessage` (first-load / gate / project-row failure), from `enrichmentErrors`
    /// (per-section read failures), and from `deleteErrorMessage` (destructive action) so
    /// a summary failure cannot clobber any of the primary detail content.
    @Published public var summaryErrorMessage: String? = nil

    // MARK: - 2.3 Risk analysis foundation state

    /// 2.3: resolved snapshot from the most recent `refreshRiskAnalysis()` call.
    /// `nil` means one of: no attempt yet, no cached row exists in `project_risk_summaries`
    /// for this project, or the most recent read failed (see `riskAnalysisErrorMessage`).
    /// Read-only — iOS 2.3 cannot trigger a fresh analysis because Web's
    /// `generateProjectRiskAnalysis(...)` is a server action with no HTTP exposure.
    @Published public var riskAnalysis: ProjectRiskAnalysis? = nil

    /// Phase 6.1: true while `refreshRiskAnalysis()` is awaiting the Web bridge response
    /// from `POST /api/ai/project-risk`. Drives the "生成中…" button state in the UI.
    ///
    /// Renamed semantically from the 2.3 "read the cached row" flow — iOS now triggers a
    /// fresh LLM-backed analysis via the bridge rather than peeking at
    /// `project_risk_summaries` directly. Kept under the same property name to avoid
    /// churning every callsite in the view; the new name would be `isGeneratingRisk`.
    @Published public var isLoadingRiskAnalysis: Bool = false
    /// Phase 6.1 alias mirroring the task brief's naming. Same value as
    /// `isLoadingRiskAnalysis`; readers may use either.
    public var isGeneratingRisk: Bool { isLoadingRiskAnalysis }

    /// 2.3: true when the most recent successful read returned ZERO cached rows. Lets the
    /// UI distinguish "haven't looked yet" from "looked, found nothing" so the user sees
    /// an honest "No risk analysis generated on the web yet for this project." hint
    /// instead of a blank card. Reset when a cached row resolves, the access gate denies,
    /// or a read error occurs (so the hint doesn't conflict with an error row).
    @Published public var riskAnalysisNotYetGenerated: Bool = false

    /// 2.3: isolated error surface for the risk analysis read. Kept separate from
    /// `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, and `summaryErrorMessage`
    /// so a transient read failure never clobbers the detail view, the enrichment
    /// sections, the destructive action surface, or the 2.2 summary foundation.
    @Published public var riskAnalysisErrorMessage: String? = nil

    // MARK: - 2.4 Linked risk actions foundation state

    /// 2.4: discrete phase of the linked-risk-actions read. Devprompt §3.C requires
    /// seven distinct states; this enum carries the ones that don't reduce to a boolean
    /// + actions array combination.
    ///
    /// - `.idle`: nothing has been tried yet for this detail instance.
    /// - `.loading`: `refreshLinkedRiskActions()` is mid-flight.
    /// - `.noRiskAnalysisSource`: step-1 of the two-step read (look up
    ///   `project_risk_summaries.id` by `project_id`) returned zero rows — meaning no
    ///   risk analysis has ever been generated on Web for this project, so there is no
    ///   `ai_source_id` anchor for `risk_actions` to link against. Distinct from
    ///   `.empty` (analysis exists but has no linked actions).
    /// - `.empty`: analysis exists, but `risk_actions.eq(ai_source_id, …)` returned zero.
    /// - `.loaded`: at least one linked action resolved; see `linkedRiskActions`.
    ///
    /// Failure is represented via `linkedRiskActionsErrorMessage`, not via a
    /// `.failure` phase, so a transient read failure does not wipe a previously
    /// resolved snapshot — the UI shows both the prior `linkedRiskActions` and a
    /// scoped error row until the next successful read. This is the Web-parity
    /// posture that `receiving-code-review` called out on 2.3: "失败时如果已经拿到
    /// 旧快照，优先保留旧快照".
    public enum LinkedRiskActionsPhase: Equatable {
        case idle
        case loading
        case noRiskAnalysisSource
        case empty
        case loaded
    }

    /// 2.4: the most recent successful snapshot of linked risk actions. Cleared by
    /// `applyDeniedState()`. Preserved across transient read failures so a flaky
    /// network call doesn't wipe valid context (see `LinkedRiskActionsPhase` docs).
    @Published public var linkedRiskActions: [ProjectLinkedRiskAction] = []

    /// 2.4: current phase of the read flow. See `LinkedRiskActionsPhase` for the state
    /// catalog. Defaults to `.idle`.
    @Published public var linkedRiskActionsPhase: LinkedRiskActionsPhase = .idle

    /// 2.4: isolated error surface for the linked-actions read. Kept separate from
    /// `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`,
    /// and `riskAnalysisErrorMessage` so a transient read failure never clobbers the
    /// detail view, the enrichment sections, the destructive action surface, the 2.2
    /// summary foundation, or the 2.3 risk analysis foundation.
    @Published public var linkedRiskActionsErrorMessage: String? = nil

    // MARK: - 2.5 Resolution feedback foundation state

    /// 2.5: discrete phase of the resolution-feedback read. Same catalog as 2.4
    /// `LinkedRiskActionsPhase` — both sections are anchored to the same
    /// `project_risk_summaries` row, so their "no source" semantics align.
    ///
    /// - `.idle`: nothing has been tried yet for this detail instance.
    /// - `.loading`: `refreshResolutionFeedback()` is mid-flight.
    /// - `.noRiskAnalysisSource`: step-1 anchor lookup returned zero rows, meaning no risk
    ///   analysis has ever been generated on Web for this project. Resolution feedback is
    ///   meaningless without that anchor.
    /// - `.empty`: anchor exists, but step-2 returned zero linked risk_actions — no
    ///   resolution history to aggregate.
    /// - `.loaded`: at least one linked action resolved; see `resolutionFeedback`.
    ///
    /// Failure is represented via `resolutionFeedbackErrorMessage`, not via a `.failure`
    /// phase, so a transient read failure does not wipe a previously resolved snapshot —
    /// mirrors the 2.4 posture (`receiving-code-review` on 2.3: "失败时如果已经拿到旧快照,
    /// 优先保留旧快照").
    public enum ResolutionFeedbackPhase: Equatable {
        case idle
        case loading
        case noRiskAnalysisSource
        case empty
        case loaded
    }

    /// 2.5: the most recent successful resolution-feedback snapshot. `nil` when no attempt
    /// has resolved yet, or the anchor doesn't exist, or the latest attempt returned no
    /// linked actions. Cleared by `applyDeniedState()`. Preserved across transient read
    /// failures so a flaky network call doesn't wipe valid context.
    @Published public var resolutionFeedback: ProjectResolutionFeedback? = nil

    /// 2.5: current phase of the read flow. See `ResolutionFeedbackPhase` for the catalog.
    /// Defaults to `.idle`.
    @Published public var resolutionFeedbackPhase: ResolutionFeedbackPhase = .idle

    /// 2.5: isolated error surface for the resolution-feedback read. Kept separate from
    /// `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`,
    /// `riskAnalysisErrorMessage`, and `linkedRiskActionsErrorMessage` so a transient read
    /// failure never clobbers the detail view, the enrichment sections, the destructive
    /// action surface, the 2.2 summary foundation, the 2.3 risk analysis foundation, or the
    /// 2.4 linked-actions foundation.
    @Published public var resolutionFeedbackErrorMessage: String? = nil

    // MARK: - 2.6 Risk action sync write path foundation state

    /// 2.6: discrete phase of the "Convert to risk action" write flow. Unlike the 2.4 / 2.5
    /// read phases, this carries a `.succeeded` terminal so the UI can flash a success hint
    /// for ~3 seconds (mirrors Web's `setTimeout(() => setSyncMsg(null), 3000)` at
    /// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` line 221). Failure is NOT
    /// modeled as a discrete phase here — the phase reverts to the pre-call phase and
    /// `riskActionSyncErrorMessage` holds the scoped failure, matching the 2.4 / 2.5
    /// "preserve prior snapshot" posture.
    ///
    /// - `.idle`: initial state; no sync attempted yet, or the last attempt's success hint
    ///   auto-cleared after 3s.
    /// - `.syncing`: the insert is mid-flight. The button is disabled, the confirmation
    ///   dialog is gone, and the success hint is not yet visible.
    /// - `.succeeded`: the insert resolved, `lastSyncedRiskActionId` is populated, and
    ///   `refreshLinkedRiskActions()` + `refreshResolutionFeedback()` have been dispatched.
    ///   The view shows "✅ 已转为风险动作" and auto-reverts to `.idle` after 3s.
    ///
    /// Confirmation presentation is NOT encoded here — the view holds its own local state
    /// for the `.confirmationDialog` because that is pure View concern.
    public enum RiskActionSyncPhase: Equatable {
        case idle
        case syncing
        case succeeded
    }

    /// 2.6: current phase of the write flow. Defaults to `.idle`. See `RiskActionSyncPhase`.
    @Published public var riskActionSyncPhase: RiskActionSyncPhase = .idle

    /// 2.6: isolated error surface for the risk-action write. Kept separate from every other
    /// error surface (`errorMessage`, `enrichmentErrors`, `deleteErrorMessage`,
    /// `summaryErrorMessage`, `riskAnalysisErrorMessage`, `linkedRiskActionsErrorMessage`,
    /// `resolutionFeedbackErrorMessage`) so a transient write failure never clobbers any
    /// read-only section or the destructive-action surface.
    @Published public var riskActionSyncErrorMessage: String? = nil

    /// 2.6: id of the most recently inserted `risk_actions` row, or `nil` when no successful
    /// sync has happened for this detail instance. Lets the view cross-check the
    /// post-success `linkedRiskActions` refresh (e.g. to highlight the new row) without the
    /// view needing to diff arrays by itself. Reset by `applyDeniedState()` on denial and by
    /// the auto-clear path when the success hint expires.
    @Published public var lastSyncedRiskActionId: UUID? = nil

    /// Records the outcome of the most recent `fetchDetail(...)` call.
    ///
    /// Mirrors Web `fetchProjectDetail()` access semantics:
    /// - `.admin`: admin+ bypassed the membership check
    /// - `.member`: non-admin caller has a matching `project_members` row
    /// - `.denied`: non-admin caller has NO `project_members` row — equivalent to Web's `'无权访问此项目'` early return
    /// - `.unknown`: never fetched yet
    ///
    /// Distinct from `errorMessage` so the view can separate "denied" from "network/decoder failure".
    public enum AccessOutcome: Equatable {
        case unknown
        case admin
        case member
        case denied
    }
    @Published public var accessOutcome: AccessOutcome = .unknown

    /// The id of the project we were asked to load. Held separately from `project` because when access
    /// is denied we clear `project` but still need to know which id the denial referred to (for retry,
    /// logging, etc.).
    public let projectId: UUID

    private let client: SupabaseClient

    public init(client: SupabaseClient, initialProject: Project) {
        self.client = client
        self.project = initialProject
        self.projectId = initialProject.id
    }

    /// Lightweight init for callers that only have the project id (e.g. Dashboard
    /// `ProjectRowCard` knows just the id from `ProjectSummary`). VM 拿到 id 后在
    /// `.task { fetchDetail() }` 里 hydrate `project`，UI 显示 loading 直到加载完。
    public init(client: SupabaseClient, projectId: UUID) {
        self.client = client
        self.project = nil
        self.projectId = projectId
    }

    /// Fetch the project detail with Web-aligned access semantics.
    ///
    /// Mirrors `fetchProjectDetail(projectId)` in `BrainStorm+-Web/src/lib/actions/projects.ts`:
    ///
    /// ```ts
    /// if (!isAdmin(guard.role)) {
    ///   const { data: membership } = await supabase
    ///     .from('project_members').select('id')
    ///     .eq('project_id', projectId).eq('user_id', guard.userId)
    ///     .maybeSingle()
    ///   if (!membership) return { data: null, error: '无权访问此项目' }
    /// }
    /// const [projectRes, tasksRes, dailyRes, weeklyRes] = await Promise.all([...])
    /// ```
    ///
    /// 1.7 scope: after the gate passes and the `projects` row is refreshed, this fans out parallel
    /// owner / tasks / daily_logs / weekly_reports queries to populate the read-only detail sections.
    /// Still out of scope: AI summary, risk analysis, linked risk actions, resolution feedback.
    ///
    /// Conservative posture — if `role`/`userId` are missing (e.g. profile not yet hydrated), this
    /// refuses to read rather than falling back to an ungated fetch. On `.denied`, ALL enrichment
    /// state is cleared so nothing leaks through the gate failure.
    public func fetchDetail(role: PrimaryRole?, userId: UUID?) async {
        isLoading = true
        errorMessage = nil

        let isAdminCaller = Self.isAdmin(role: role)

        do {
            if !isAdminCaller {
                // Non-admin MUST pass the project_members gate.
                guard let userId else {
                    applyDeniedState()
                    isLoading = false
                    return
                }

                let isMember = try await checkMembership(userId: userId)
                if !isMember {
                    applyDeniedState()
                    isLoading = false
                    return
                }
                self.accessOutcome = .member
            } else {
                self.accessOutcome = .admin
            }

            let refreshed: Project = try await client
                .from("projects")
                .select()
                .eq("id", value: projectId)
                .single()
                .execute()
                .value
            self.project = refreshed

            // Gate passed + project row fetched. Fan out enrichment in parallel. Each sub-fetch
            // captures its own error into `enrichmentErrors[...]` so one failure does not nuke
            // the rest of the detail view.
            await loadEnrichment(for: refreshed)
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }

        isLoading = false
    }

    // MARK: - Denied-state reset

    /// Clears `project` and ALL 1.7 / 1.8 enrichment state. Called on every denied path so a
    /// non-member cannot keep reading seeded data, stale enrichment, or hydrated profile names
    /// from a prior successful fetch.
    ///
    /// 2.2: also clears AI summary state so a denied caller can't keep reading a snapshot
    /// synthesized during a prior successful fetch.
    ///
    /// 2.3: also clears risk analysis state so a denied caller can't keep reading a cached
    /// risk snapshot from `project_risk_summaries` fetched during a prior successful access.
    ///
    /// 2.4: also clears linked risk actions state so a denied caller can't keep reading
    /// `risk_actions` rows resolved during a prior successful access.
    ///
    /// 2.5: also clears resolution feedback aggregate so a denied caller can't keep
    /// reading resolution counts / recent resolutions aggregated during a prior
    /// successful access.
    ///
    /// 2.6: also resets the risk-action sync write state so a denied caller can't keep
    /// seeing a success hint / last-synced id / in-flight phase from a prior privileged
    /// access. The server-side RLS policy already bars the write, but the UI-level reset
    /// keeps the affordance consistent with every other denied-on-detail behavior.
    private func applyDeniedState() {
        self.project = nil
        self.owner = nil
        self.tasks = []
        self.dailyLogs = []
        self.weeklySummaries = []
        self.profilesById = [:]
        self.enrichmentErrors = [:]
        self.projectSummary = nil
        self.summaryErrorMessage = nil
        self.riskAnalysis = nil
        self.riskAnalysisErrorMessage = nil
        self.riskAnalysisNotYetGenerated = false
        self.linkedRiskActions = []
        self.linkedRiskActionsPhase = .idle
        self.linkedRiskActionsErrorMessage = nil
        self.resolutionFeedback = nil
        self.resolutionFeedbackPhase = .idle
        self.resolutionFeedbackErrorMessage = nil
        self.riskActionSyncPhase = .idle
        self.riskActionSyncErrorMessage = nil
        self.lastSyncedRiskActionId = nil
        self.accessOutcome = .denied
    }

    // MARK: - Admin predicate

    private static func isAdmin(role: PrimaryRole?) -> Bool {
        switch role {
        case .admin, .superadmin: return true
        case .employee, .none: return false
        }
    }

    // MARK: - Membership check

    /// The Swift SDK at this version does not expose `maybeSingle()`, so we run a plain `select` on
    /// `project_members` scoped by both `project_id` and `user_id` and treat an empty result as
    /// "not a member" — semantically equivalent to Web's `!membership` early return.
    private struct MembershipCheckRow: Decodable { let id: UUID }

    private func checkMembership(userId: UUID) async throws -> Bool {
        let rows: [MembershipCheckRow] = try await client
            .from("project_members")
            .select("id")
            .eq("project_id", value: projectId)
            .eq("user_id", value: userId)
            .execute()
            .value
        return !rows.isEmpty
    }

    // MARK: - 1.7 Enrichment

    /// Runs owner + tasks + daily_logs + weekly_reports fetches in parallel.
    ///
    /// Each sub-fetch is wrapped so a failure is recorded in `enrichmentErrors[.section]` rather
    /// than thrown — the detail page should keep rendering the `projects` row even if one sub-query
    /// fails. Fresh errors overwrite stale ones; sections that succeed clear their previous error.
    private func loadEnrichment(for project: Project) async {
        isLoadingEnrichment = true
        // Reset per-section errors at the start of an enrichment pass. Individual sub-tasks
        // repopulate `enrichmentErrors[...]` on failure, or keep it clear on success.
        self.enrichmentErrors = [:]

        async let ownerFetch: Void = fetchOwner(ownerId: project.ownerId)
        async let tasksFetch: Void = fetchTasks()
        async let dailyFetch: Void = fetchDailyLogs()
        async let weeklyFetch: Void = fetchWeeklySummaries()

        _ = await (ownerFetch, tasksFetch, dailyFetch, weeklyFetch)

        // 1.8: batched nested-name hydration for task assignees + daily / weekly authors. Runs ONLY
        // after the sections resolve because that's when we know which ids to ask about. This is a
        // single `profiles.in("id", values: ids)` round trip — explicitly NOT N+1 per row.
        await hydrateSublistProfiles()

        isLoadingEnrichment = false
    }

    private func fetchOwner(ownerId: UUID?) async {
        guard let ownerId else {
            self.owner = nil
            return
        }
        do {
            let rows: [ProjectOwnerSummary] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url")
                .eq("id", value: ownerId)
                .limit(1)
                .execute()
                .value
            self.owner = rows.first
        } catch {
            self.owner = nil
            self.enrichmentErrors[.owner] = ErrorLocalizer.localize(error)
        }
    }

    /// Mirrors Web:
    /// ```ts
    /// adminDb.from('tasks')
    ///   .select('id, title, status, priority, assignee_id, ...')
    ///   .eq('project_id', projectId)
    ///   .order('created_at', { ascending: false })
    ///   .limit(50)
    /// ```
    private func fetchTasks() async {
        do {
            let rows: [ProjectTaskSummary] = try await client
                .from("tasks")
                .select("id, title, status, priority, assignee_id")
                .eq("project_id", value: projectId)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            self.tasks = rows
        } catch {
            self.tasks = []
            self.enrichmentErrors[.tasks] = ErrorLocalizer.localize(error)
        }
    }

    /// Mirrors Web:
    /// ```ts
    /// adminDb.from('daily_logs')
    ///   .select('id, date, content, progress, blockers, ...')
    ///   .eq('project_id', projectId)
    ///   .order('date', { ascending: false })
    ///   .limit(10)
    /// ```
    private func fetchDailyLogs() async {
        do {
            let rows: [ProjectDailyLogSummary] = try await client
                .from("daily_logs")
                // 1.8: added `user_id` so the follow-up `hydrateSublistProfiles()` can resolve
                // per-row author names via a single batched `profiles.in("id", values: ...)` call.
                .select("id, date, content, progress, blockers, user_id")
                .eq("project_id", value: projectId)
                .order("date", ascending: false)
                .limit(10)
                .execute()
                .value
            self.dailyLogs = rows
        } catch {
            self.dailyLogs = []
            self.enrichmentErrors[.dailyLogs] = ErrorLocalizer.localize(error)
        }
    }

    /// Mirrors Web:
    /// ```ts
    /// adminDb.from('weekly_reports')
    ///   .select('id, week_start, summary, highlights, challenges, ...')
    ///   .contains('project_ids', [projectId])
    ///   .order('week_start', { ascending: false })
    ///   .limit(5)
    /// ```
    ///
    /// Note: `project_ids` is a Postgres `text[]` (or `uuid[]`) array column. The Swift SDK's
    /// `.contains(_:value:)` serializes `[String]` as `{v1,v2}`, which PostgREST translates into
    /// `cs.{v1,v2}` — i.e. array-contains, equivalent to Web's `.contains('project_ids', [projectId])`.
    private func fetchWeeklySummaries() async {
        do {
            let rows: [ProjectWeeklySummary] = try await client
                .from("weekly_reports")
                // 1.8: added `user_id` for the same sublist-profile hydrate as daily logs.
                .select("id, week_start, summary, highlights, challenges, user_id")
                .contains("project_ids", value: [projectId.uuidString])
                .order("week_start", ascending: false)
                .limit(5)
                .execute()
                .value
            self.weeklySummaries = rows
        } catch {
            self.weeklySummaries = []
            self.enrichmentErrors[.weeklySummaries] = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - 1.8 Nested profile hydration

    /// Batched replacement for Web's nested `profiles:assignee_id(full_name)` /
    /// `profiles:user_id(full_name)` selects inside `fetchProjectDetail()`.
    ///
    /// Collects every distinct non-nil id referenced by `tasks[].assigneeId`,
    /// `dailyLogs[].userId`, `weeklySummaries[].userId`, excludes the owner id we already
    /// resolved (to avoid re-fetching the same row), and issues ONE PostgREST call:
    ///
    /// ```swift
    /// .from("profiles").select("id, full_name, avatar_url").in("id", values: ids)
    /// ```
    ///
    /// Failure mode is deliberately softer than a section fetch: we record
    /// `enrichmentErrors[.sublistProfiles]` but do NOT clear the section rows themselves —
    /// tasks / daily logs / weekly summaries remain visible, just with UUID fallback where
    /// the name can't be resolved.
    private func hydrateSublistProfiles() async {
        var ids = Set<UUID>()
        for t in tasks {
            if let a = t.assigneeId { ids.insert(a) }
        }
        for l in dailyLogs {
            if let u = l.userId { ids.insert(u) }
        }
        for w in weeklySummaries {
            if let u = w.userId { ids.insert(u) }
        }
        if let ownerId = owner?.id {
            // Already hydrated via `fetchOwner`; no need to re-fetch.
            ids.remove(ownerId)
        }

        guard !ids.isEmpty else {
            self.profilesById = [:]
            return
        }

        do {
            let rows: [ProjectOwnerSummary] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url")
                .in("id", values: Array(ids))
                .execute()
                .value
            var map: [UUID: ProjectOwnerSummary] = [:]
            for row in rows { map[row.id] = row }
            self.profilesById = map
        } catch {
            // Keep previously rendered sections intact; only surface a soft per-section error.
            self.profilesById = [:]
            self.enrichmentErrors[.sublistProfiles] = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - 2.0 Delete

    /// Mirrors Web `deleteProject(id)`:
    ///
    /// ```ts
    /// const { error } = await supabase.from('projects').delete().eq('id', id)
    /// ```
    ///
    /// Target is the `projects` row; `project_members` cascade-deletes via a Postgres FK, so
    /// iOS does not re-implement cascade logic. On success `project` is cleared so the view
    /// can dismiss without flashing deleted row data during the pop animation. The caller is
    /// responsible for invoking `dismiss()` and notifying the list (via `onProjectDeleted`).
    ///
    /// Access gate: callers must only expose the delete entry when `accessOutcome != .denied`
    /// and `project != nil`. This VM does not re-check the gate here because the gate is a
    /// UI-shaping layer; real authorization lives in Supabase RLS. A denied user who somehow
    /// triggers this will get an RLS failure surfaced through `deleteErrorMessage`.
    public func deleteProject() async -> Bool {
        isDeleting = true
        deleteErrorMessage = nil
        do {
            _ = try await client
                .from("projects")
                .delete()
                .eq("id", value: projectId)
                .execute()
            self.project = nil
            isDeleting = false
            return true
        } catch {
            deleteErrorMessage = ErrorLocalizer.localize(error)
            isDeleting = false
            return false
        }
    }

    // MARK: - 1.8 Display helpers

    /// Resolves a user id to a human-readable name using the 1.8 profile hydrate. Falls back to
    /// the 1.7 owner lookup when the id happens to be the project owner (we skipped it in the
    /// batch query to avoid a redundant fetch). Returns `nil` when we truly can't resolve —
    /// callers decide whether to show the id or hide the byline.
    public func displayName(forUserId userId: UUID?) -> String? {
        guard let userId else { return nil }
        if let profile = profilesById[userId], let name = profile.fullName, !name.isEmpty {
            return name
        }
        if let owner, owner.id == userId, let name = owner.fullName, !name.isEmpty {
            return name
        }
        return nil
    }

    // MARK: - 2.2 AI summary foundation (retired — replaced by Web bridge in Phase 6.1)

    // 已切换到 Web bridge /api/ai/project-summary —— 以下三个本地合成 DTO 原用于
    // 复刻 Web `generateProjectSummary` 的并行 Supabase 读。新流程下不再需要它们，
    // 保留为注释以方便后续回溯字段对齐。
    //
    // private struct ProjectSummaryTaskRow: Decodable {
    //     let title: String
    //     let status: String
    //     let priority: String?
    //     let dueDate: String?
    //     enum CodingKeys: String, CodingKey {
    //         case title, status, priority
    //         case dueDate = "due_date"
    //     }
    // }
    //
    // private struct ProjectSummaryDailyRow: Decodable {
    //     let date: String
    //     let content: String?
    //     let progress: String?
    //     let blockers: String?
    // }
    //
    // private struct ProjectSummaryWeeklyRow: Decodable {
    //     let weekStart: String
    //     let summary: String?
    //     let highlights: String?
    //     let challenges: String?
    //     enum CodingKeys: String, CodingKey {
    //         case weekStart = "week_start"
    //         case summary, highlights, challenges
    //     }
    // }

    /// Fan out the same parallel Supabase reads Web's `generateProjectSummary(projectId)` runs,
    /// then synthesize a deterministic facts-only foundation summary.
    ///
    /// **Web source-of-truth discrepancy (2.2)**: Web's `generateProjectSummary` is a server
    /// action in `BrainStorm+-Web/src/lib/actions/summary-actions.ts`; it is NOT exposed as an
    /// HTTP API route and internally decrypts org provider credentials from the `api_keys`
    /// table before calling `askAI(...)`. iOS cannot reach that server action directly without
    /// a Web-side change (new `/api/ai/project-summary/route.ts` or equivalent Supabase Edge
    /// Function). 2.2 therefore ships the iOS-side foundation: iOS mirrors Web's exact
    /// parallel fetch (same tables, same filters, same row limits — 30 tasks / 10 daily logs /
    /// 3 weekly reports) and synthesizes a deterministic facts summary locally. When the
    /// server endpoint lands, only the synthesis step has to change; the UI / VM state shape
    /// stays stable.
    ///
    /// Failure isolation (devprompt §3.C):
    /// - On failure only `summary` is cleared and `summaryErrorMessage` is set.
    /// - Does NOT touch `project`, `tasks`, `dailyLogs`, `weeklySummaries`, `owner`,
    ///   `profilesById`, `errorMessage`, `enrichmentErrors`, or `deleteErrorMessage`.
    /// - A counting-style "not enough data" outcome (mirrors Web's `项目暂无足够数据生成摘要`
    ///   branch) is surfaced through `summaryErrorMessage`, not as a silent empty success.
    public func generateSummary() async {
        // `projectId` is a non-optional `let`, but we still preserve an explicit guard
        // to match the pattern used by `refreshRiskAnalysis()` and keep the failure
        // branch self-documenting if the constructor shape ever changes.
        let targetId = self.project?.id ?? self.projectId

        isGeneratingSummary = true
        summaryErrorMessage = nil

        // 已切换到 Web bridge /api/ai/project-summary —— 原本地合成逻辑已废弃，
        // 保留在 `synthesizeFoundationSummary(...)` 注释块里以供回溯。
        do {
            let session = try await client.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/ai/project-summary")

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 90

            let payload: [String: Any] = ["project_id": targetId.uuidString]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                self.summaryErrorMessage = "摘要生成失败：网络异常，请稍后重试"
                isGeneratingSummary = false
                return
            }

            if http.statusCode >= 400 {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let serverError = (json?["error"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(http.statusCode)"
                self.summaryErrorMessage = "摘要生成失败：\(serverError)"
                self.projectSummary = nil
                isGeneratingSummary = false
                return
            }

            let decoded = try JSONDecoder().decode(ProjectSummary.self, from: data)
            self.projectSummary = decoded
            self.summaryErrorMessage = nil
        } catch {
            self.projectSummary = nil
            self.summaryErrorMessage = "摘要生成失败：\(ErrorLocalizer.localize(error))"
        }

        isGeneratingSummary = false
    }

    // 已切换到 Web bridge /api/ai/project-summary —— 以下本地合成函数连同
    // 它使用的日期格式化器、humanize 辅助函数一起停用。保留为注释块，便于后续
    // 当 Web 端还没 ready 需要回滚时直接复原。类型签名里引用的 ProjectSummaryTaskRow
    // / ProjectSummaryDailyRow / ProjectSummaryWeeklyRow / ProjectSummaryFoundation
    // 都已在上方同步注释。
    //
    // private static func synthesizeFoundationSummary(
    //     project: Project,
    //     tasks: [ProjectSummaryTaskRow],
    //     dailyLogs: [ProjectSummaryDailyRow],
    //     weeklyReports: [ProjectSummaryWeeklyRow]
    // ) -> ProjectSummaryFoundation {
    //     let todayString = Self.iso8601DateOnlyFormatter.string(from: Date())
    //     let doneCount = tasks.filter { $0.status == "done" }.count
    //     let inProgressCount = tasks.filter { $0.status == "in_progress" }.count
    //     let overdueCount = tasks.filter { row in
    //         guard let due = row.dueDate, !due.isEmpty else { return false }
    //         return due < todayString && row.status != "done"
    //     }.count
    //     var sections: [String] = []
    //     var overviewLine = "Status: \(Self.humanize(project.status.rawValue)) · Progress: \(project.progress)%"
    //     if let end = project.endDate {
    //         overviewLine += " · End date: \(Self.displayDateFormatter.string(from: end))"
    //     }
    //     sections.append("Overview\n\(overviewLine)")
    //     if !tasks.isEmpty {
    //         var taskLines: [String] = []
    //         taskLines.append("Total \(tasks.count) · \(doneCount) done · \(inProgressCount) in progress · \(overdueCount) overdue")
    //         let preview = tasks.prefix(5).map { "• [\(Self.humanize($0.status))] \($0.title)" }
    //         taskLines.append(contentsOf: preview)
    //         if tasks.count > 5 {
    //             taskLines.append("… and \(tasks.count - 5) more")
    //         }
    //         sections.append("Tasks\n" + taskLines.joined(separator: "\n"))
    //     }
    //     if !dailyLogs.isEmpty {
    //         var lines: [String] = ["\(dailyLogs.count) recent log\(dailyLogs.count == 1 ? "" : "s")"]
    //         if let latest = dailyLogs.first {
    //             let trimmedContent = (latest.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    //             let snippet = trimmedContent.isEmpty ? "(no content)" : String(trimmedContent.prefix(160))
    //             lines.append("Latest (\(latest.date)): \(snippet)")
    //             if let blockers = latest.blockers, !blockers.isEmpty {
    //                 lines.append("Blockers: \(blockers)")
    //             }
    //         }
    //         sections.append("Recent activity\n" + lines.joined(separator: "\n"))
    //     }
    //     if !weeklyReports.isEmpty {
    //         var lines: [String] = ["\(weeklyReports.count) recent weekly report\(weeklyReports.count == 1 ? "" : "s")"]
    //         if let latest = weeklyReports.first {
    //             if let s = latest.summary, !s.isEmpty {
    //                 lines.append("Week of \(latest.weekStart): \(String(s.prefix(200)))")
    //             }
    //             if let highlights = latest.highlights, !highlights.isEmpty {
    //                 lines.append("Highlights: \(String(highlights.prefix(160)))")
    //             }
    //             if let challenges = latest.challenges, !challenges.isEmpty {
    //                 lines.append("Challenges: \(String(challenges.prefix(160)))")
    //             }
    //         }
    //         sections.append("Weekly reports\n" + lines.joined(separator: "\n"))
    //     }
    //     let body = sections.joined(separator: "\n\n")
    //     return ProjectSummaryFoundation(
    //         summary: body,
    //         generatedAt: Date(),
    //         facts: .init(
    //             taskTotal: tasks.count,
    //             taskDone: doneCount,
    //             taskInProgress: inProgressCount,
    //             taskOverdue: overdueCount,
    //             dailyLogCount: dailyLogs.count,
    //             weeklyReportCount: weeklyReports.count
    //         )
    //     )
    // }
    //
    // private static func humanize(_ raw: String) -> String {
    //     raw.replacingOccurrences(of: "_", with: " ").capitalized
    // }
    //
    // private static let iso8601DateOnlyFormatter: DateFormatter = { ... }()
    // private static let displayDateFormatter: DateFormatter = { ... }()

    // MARK: - 2.3 Risk analysis foundation

    /// Private decode shape for a single `project_risk_summaries` row, projected to the
    /// columns the foundation UI needs: `summary`, `risk_level`, `generated_at`,
    /// `model_used`, `scenario`. Kept private to the VM; not exposed through
    /// `ProjectDetailModels` because callers only ever need the resolved
    /// `ProjectRiskAnalysis`.
    private struct ProjectRiskRow: Decodable {
        let summary: String?
        let riskLevel: String?
        let generatedAt: String?
        let modelUsed: String?
        let scenario: String?

        enum CodingKeys: String, CodingKey {
            case summary
            case riskLevel = "risk_level"
            case generatedAt = "generated_at"
            case modelUsed = "model_used"
            case scenario
        }
    }

    /// Read the most recent cached risk analysis row for this project.
    ///
    /// **Web source-of-truth discrepancy (2.3)**: Web's `generateProjectRiskAnalysis(projectId)`
    /// is a server action, not an HTTP route. iOS cannot trigger a new analysis without a
    /// Web-side endpoint (nor should it — the server action decrypts org provider credentials
    /// before calling `askAI`, which must never land on-device). Risk analysis DOES persist
    /// (`project_risk_summaries`, keyed by `project_id`, upserted on each Web-side regenerate),
    /// so iOS 2.3 reads that row directly and displays it read-only.
    ///
    /// Wire shape:
    /// ```swift
    /// .from("project_risk_summaries")
    ///   .select("summary, risk_level, generated_at, model_used, scenario")
    ///   .eq("project_id", value: projectId)
    ///   .limit(1)
    /// ```
    /// The Swift SDK at this version does not expose `.maybeSingle()`, so we query as an
    /// array and treat `rows.first` as the row (mirrors the 1.6 membership gate pattern).
    /// A zero-row result is NOT a failure; it's simply "no Web-side analysis exists yet",
    /// surfaced via `riskAnalysisNotYetGenerated = true`.
    ///
    /// Failure isolation (devprompt §3.C):
    /// - On failure only `riskAnalysisErrorMessage` is set; `riskAnalysis` is preserved so a
    ///   transient read failure doesn't wipe a previously resolved snapshot.
    /// - Does NOT touch `project`, `tasks`, `dailyLogs`, `weeklySummaries`, `owner`,
    ///   `profilesById`, `enrichmentErrors`, `errorMessage`, `deleteErrorMessage`,
    ///   `summary`, or `summaryErrorMessage`.
    /// - Does not fire any LLM call, does not read `api_keys`, does not write anywhere.
    public func refreshRiskAnalysis() async {
        isLoadingRiskAnalysis = true
        riskAnalysisErrorMessage = nil

        // 已切换到 Web bridge /api/ai/project-risk —— 原本地直读
        // `project_risk_summaries` 的逻辑保留在下方注释块,便于回滚。
        do {
            let session = try await client.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/ai/project-risk")

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 90

            let payload: [String: Any] = ["project_id": projectId.uuidString]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                self.riskAnalysisErrorMessage = "风险分析生成失败：网络异常，请稍后重试"
                self.riskAnalysisNotYetGenerated = false
                isLoadingRiskAnalysis = false
                return
            }

            if http.statusCode >= 400 {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let serverError = (json?["error"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(http.statusCode)"
                self.riskAnalysisErrorMessage = "风险分析生成失败：\(serverError)"
                self.riskAnalysisNotYetGenerated = false
                isLoadingRiskAnalysis = false
                return
            }

            let decoded = try JSONDecoder().decode(ProjectRiskAnalysisResponse.self, from: data)
            let resolvedLevelRaw = decoded.riskLevel ?? decoded.overallRiskLevel
            self.riskAnalysis = ProjectRiskAnalysis(
                summary: decoded.summary,
                riskLevel: Self.parseRiskLevel(resolvedLevelRaw),
                risks: decoded.risks,
                generatedAt: Self.parseTimestamp(decoded.generatedAt),
                model: decoded.modelUsed,
                scenario: decoded.scenario
            )
            self.riskAnalysisNotYetGenerated = false
        } catch {
            self.riskAnalysisErrorMessage = "风险分析生成失败：\(ErrorLocalizer.localize(error))"
            self.riskAnalysisNotYetGenerated = false
        }

        isLoadingRiskAnalysis = false
    }

    // 已切换到 Web bridge /api/ai/project-risk —— 以下原本地读取 project_risk_summaries
    // 的逻辑停用,保留为注释块便于回滚对照。
    //
    // public func refreshRiskAnalysis() async {
    //     isLoadingRiskAnalysis = true
    //     riskAnalysisErrorMessage = nil
    //     do {
    //         let rows: [ProjectRiskRow] = try await client
    //             .from("project_risk_summaries")
    //             .select("summary, risk_level, generated_at, model_used, scenario")
    //             .eq("project_id", value: projectId)
    //             .limit(1)
    //             .execute()
    //             .value
    //         if let row = rows.first, let text = row.summary,
    //            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    //             self.riskAnalysis = ProjectRiskAnalysis(
    //                 summary: text,
    //                 riskLevel: Self.parseRiskLevel(row.riskLevel),
    //                 generatedAt: Self.parseTimestamp(row.generatedAt),
    //                 model: row.modelUsed,
    //                 scenario: row.scenario
    //             )
    //             self.riskAnalysisNotYetGenerated = false
    //         } else {
    //             self.riskAnalysis = nil
    //             self.riskAnalysisNotYetGenerated = true
    //         }
    //     } catch {
    //         self.riskAnalysisErrorMessage = ErrorLocalizer.localize(error)
    //         self.riskAnalysisNotYetGenerated = false
    //     }
    //     isLoadingRiskAnalysis = false
    // }

    private static func parseRiskLevel(_ raw: String?) -> ProjectRiskAnalysis.RiskLevel {
        guard let lower = raw?.lowercased() else { return .unknown }
        return ProjectRiskAnalysis.RiskLevel(rawValue: lower) ?? .unknown
    }

    /// Postgres `timestamptz` columns come back as ISO8601 strings with or without fractional
    /// seconds; try both shapes and fall back to `nil` rather than throwing — the provenance
    /// caption simply hides the timestamp line when parsing fails.
    private static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = iso8601FractionalFormatter.date(from: raw) { return d }
        if let d = iso8601PlainFormatter.date(from: raw) { return d }
        return nil
    }

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601PlainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - 2.4 Linked risk actions foundation

    /// Minimal decode shape for the step-1 lookup (`project_risk_summaries.id` keyed by
    /// `project_id`). Kept private because callers outside the VM never need it — the
    /// resolved anchor id is immediately consumed by step-2 and discarded.
    private struct LinkedRiskAnchorRow: Decodable {
        let id: UUID
    }

    /// Two-step read of risk actions linked to this project's cached risk analysis.
    ///
    /// **Web source-of-truth (2.4)**: mirrors `getLinkedRiskActions(projectId)` in
    /// `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (lines 597-626):
    ///
    /// ```ts
    /// const { data: summary } = await supabase
    ///   .from('project_risk_summaries').select('id')
    ///   .eq('project_id', projectId).maybeSingle()
    /// if (!summary) return { data: [], error: null }
    /// const { data } = await supabase
    ///   .from('risk_actions')
    ///   .select('id, title, status, severity, ai_source_id')
    ///   .eq('ai_source_id', summary.id)
    ///   .order('created_at', { ascending: false })
    ///   .limit(20)
    /// ```
    ///
    /// iOS cannot call the server action directly, but both tables are readable via
    /// PostgREST under the org-scoped RLS policies (see `037_round8_risk_knowledge_ai.sql`
    /// + `014_add_risk_action_ai_source.sql`). This is a faithful read-only replica of
    /// the server-action flow.
    ///
    /// **Why two queries instead of a nested select**: the Swift SDK at this version
    /// doesn't cleanly express `risk_actions!ai_source_id(project_risk_summaries!inner(…))`-style
    /// nested filters in a way that decodes into flat `Codable` DTOs, and we already use
    /// two-step / batched-follow-up patterns elsewhere in this VM (1.8 sublist profile
    /// hydrate, 1.6 membership gate). Two small round trips are fine at foundation scope.
    ///
    /// **State transitions**:
    /// - `.idle` / `.loaded` / `.empty` / `.noRiskAnalysisSource` → `.loading` on entry.
    /// - Step-1 returns zero rows → `.noRiskAnalysisSource` (distinct from `.empty`).
    /// - Step-2 returns zero rows → `.empty`.
    /// - Step-2 returns rows → `.loaded` + `linkedRiskActions = rows`.
    /// - Any throw during either step → prior snapshot preserved; error message set;
    ///   phase reverts to whatever it was before the call if that phase is still
    ///   representative, otherwise falls back to `.idle`.
    ///
    /// **Failure isolation (devprompt §3.D)**:
    /// - Only `linkedRiskActionsErrorMessage` is written on the failure path.
    /// - Does NOT touch `project`, `tasks`, `dailyLogs`, `weeklySummaries`, `owner`,
    ///   `profilesById`, `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`,
    ///   `summary`, `summaryErrorMessage`, `riskAnalysis`, or `riskAnalysisErrorMessage`.
    /// - Does not invoke any LLM, does not read `api_keys`, does not write anywhere.
    public func refreshLinkedRiskActions() async {
        // Preserve the pre-call phase so a failure can drop us back into a sensible
        // state (e.g. if we were already `.loaded`, stay `.loaded` on a transient read
        // fail and just surface the scoped error — the snapshot is still valid).
        let priorPhase = linkedRiskActionsPhase
        linkedRiskActionsPhase = .loading
        linkedRiskActionsErrorMessage = nil

        do {
            let anchorRows: [LinkedRiskAnchorRow] = try await client
                .from("project_risk_summaries")
                .select("id")
                .eq("project_id", value: projectId)
                .limit(1)
                .execute()
                .value

            guard let anchor = anchorRows.first else {
                // No risk analysis has ever been generated on Web for this project.
                // Distinct from `.empty` — the UI shows "run a risk analysis on Web
                // first" rather than "no actions yet".
                self.linkedRiskActionsPhase = .noRiskAnalysisSource
                self.linkedRiskActions = []
                return
            }

            let actions: [ProjectLinkedRiskAction] = try await client
                .from("risk_actions")
                .select("id, title, status, severity, ai_source_id")
                .eq("ai_source_id", value: anchor.id)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            if actions.isEmpty {
                self.linkedRiskActionsPhase = .empty
                self.linkedRiskActions = []
            } else {
                self.linkedRiskActionsPhase = .loaded
                self.linkedRiskActions = actions
            }
        } catch {
            // Preserve prior snapshot: don't wipe `linkedRiskActions`; don't touch any
            // other error surface. Revert phase so the UI doesn't stay stuck on
            // "Loading…" — fall back to whatever the VM knew before the call.
            self.linkedRiskActionsErrorMessage = ErrorLocalizer.localize(error)
            self.linkedRiskActionsPhase = (priorPhase == .loading) ? .idle : priorPhase
        }
    }

    // MARK: - 2.5 Resolution feedback foundation

    /// Minimal decode shape for step-2 of the resolution-feedback read. Matches Web's
    /// projection exactly: `title, status, severity, resolution_category, effectiveness,
    /// follow_up_required, reopen_count, resolved_at`. Nullable fields are modeled as
    /// optionals so a row with a missing `resolution_category` / `effectiveness` / etc.
    /// doesn't crash decode. `resolvedAt` stays `String?` because Postgres `timestamptz`
    /// can come back with fractional seconds or not; we parse on render in the VM helpers,
    /// not on decode. Kept private to the VM.
    private struct ResolutionFeedbackRow: Decodable {
        let title: String
        let status: String
        let severity: String?
        let resolutionCategory: String?
        let effectiveness: String?
        let followUpRequired: Bool?
        let reopenCount: Int?
        let resolvedAt: String?

        enum CodingKeys: String, CodingKey {
            case title
            case status
            case severity
            case resolutionCategory = "resolution_category"
            case effectiveness
            case followUpRequired = "follow_up_required"
            case reopenCount = "reopen_count"
            case resolvedAt = "resolved_at"
        }
    }

    /// Two-step read that aggregates resolution feedback for this project's risk analysis.
    ///
    /// **Web source-of-truth (2.5)**: mirrors `getProjectRiskResolutionSummary(projectId)` in
    /// `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (lines 630-714):
    ///
    /// ```ts
    /// // Step 1 — anchor
    /// const { data: summary } = await supabase
    ///   .from('project_risk_summaries').select('id')
    ///   .eq('project_id', projectId).maybeSingle()
    /// if (!summary) return { data: null, error: null }
    ///
    /// // Step 2 — filtered select
    /// const { data } = await supabase
    ///   .from('risk_actions')
    ///   .select('title, status, severity, resolution_category, effectiveness,
    ///           follow_up_required, reopen_count, resolved_at')
    ///   .eq('ai_source_id', summary.id)
    ///   .order('resolved_at', { ascending: false, nullsFirst: false })
    ///   .limit(50)
    ///
    /// // Then aggregate: counts + dominantCategory + recentResolutions (top 3 of
    /// // status in {resolved, dismissed})
    /// ```
    ///
    /// Aggregation is **client-side** and therefore `total` caps at 50, matching Web's
    /// behavior exactly. This is not a source-of-truth divergence — it's Web's own
    /// contract.
    ///
    /// **No server secrets**: no `askAI()`, no `decryptApiKey()`, no `api_keys` access.
    /// iOS replicates the flow faithfully via direct PostgREST. Same posture as 2.4
    /// `getLinkedRiskActions`.
    ///
    /// **State transitions** (mirrors 2.4):
    /// - `.idle` / `.loaded` / `.empty` / `.noRiskAnalysisSource` → `.loading` on entry.
    /// - Step-1 zero rows → `.noRiskAnalysisSource`, `resolutionFeedback = nil`, return.
    /// - Step-2 zero rows → `.empty`, `resolutionFeedback = nil`.
    /// - Step-2 rows → `.loaded`, `resolutionFeedback = aggregated`.
    /// - Any throw → prior snapshot preserved; error message set; phase reverts to
    ///   whatever it was before (or `.idle` if we were in `.loading`).
    ///
    /// **Failure isolation (devprompt §3.D)**:
    /// - Only `resolutionFeedbackErrorMessage` is written on the failure path.
    /// - Does NOT touch `project`, `tasks`, `dailyLogs`, `weeklySummaries`, `owner`,
    ///   `profilesById`, `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`,
    ///   `summary`, `summaryErrorMessage`, `riskAnalysis`, `riskAnalysisErrorMessage`,
    ///   `linkedRiskActions`, or `linkedRiskActionsErrorMessage`.
    public func refreshResolutionFeedback() async {
        let priorPhase = resolutionFeedbackPhase
        resolutionFeedbackPhase = .loading
        resolutionFeedbackErrorMessage = nil

        do {
            let anchorRows: [LinkedRiskAnchorRow] = try await client
                .from("project_risk_summaries")
                .select("id")
                .eq("project_id", value: projectId)
                .limit(1)
                .execute()
                .value

            guard let anchor = anchorRows.first else {
                self.resolutionFeedbackPhase = .noRiskAnalysisSource
                self.resolutionFeedback = nil
                return
            }

            let rows: [ResolutionFeedbackRow] = try await client
                .from("risk_actions")
                .select("title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at")
                .eq("ai_source_id", value: anchor.id)
                .order("resolved_at", ascending: false, nullsFirst: false)
                .limit(50)
                .execute()
                .value

            if rows.isEmpty {
                self.resolutionFeedbackPhase = .empty
                self.resolutionFeedback = nil
            } else {
                self.resolutionFeedback = Self.aggregateResolutionFeedback(rows: rows)
                self.resolutionFeedbackPhase = .loaded
            }
        } catch {
            self.resolutionFeedbackErrorMessage = ErrorLocalizer.localize(error)
            self.resolutionFeedbackPhase = (priorPhase == .loading) ? .idle : priorPhase
        }
    }

    /// Aggregate helper — runs the exact counts Web runs client-side, then picks the top-3
    /// resolved/dismissed rows (preserving the server-side `resolved_at DESC` order that
    /// step-2 already applied) for the recent-resolutions list.
    ///
    /// `dominantCategory` is the most-frequent non-nil `resolution_category` across the
    /// entire row set. Ties break by first-encountered (stable across runs because rows
    /// arrive in `resolved_at DESC` order).
    private static func aggregateResolutionFeedback(
        rows: [ResolutionFeedbackRow]
    ) -> ProjectResolutionFeedback {
        let total = rows.count
        let resolved = rows.filter { $0.status == "resolved" }.count
        let dismissed = rows.filter { $0.status == "dismissed" }.count
        let active = rows.filter { row in
            row.status == "open" || row.status == "acknowledged" || row.status == "in_progress"
        }.count
        let followUpRequired = rows.filter { $0.followUpRequired == true }.count
        let reopenedCount = rows.filter { ($0.reopenCount ?? 0) > 0 }.count

        // Dominant category: count occurrences of non-nil `resolution_category` and take the
        // max. Ties → first-encountered (rows already in `resolved_at DESC`).
        var categoryCounts: [(String, Int)] = []
        for row in rows {
            guard let category = row.resolutionCategory, !category.isEmpty else { continue }
            if let idx = categoryCounts.firstIndex(where: { $0.0 == category }) {
                categoryCounts[idx].1 += 1
            } else {
                categoryCounts.append((category, 1))
            }
        }
        let dominantCategory: String? = categoryCounts.max(by: { $0.1 < $1.1 })?.0

        // Recent resolutions: top 3 resolved/dismissed. `rows` is already ordered by
        // `resolved_at DESC NULLS LAST`, so `prefix(3)` after filter matches Web's
        // ordering exactly (Web also filters to resolved/dismissed before the slice).
        let recent = rows
            .filter { $0.status == "resolved" || $0.status == "dismissed" }
            .prefix(3)
            .map { row in
                ProjectResolutionFeedback.RecentResolution(
                    title: row.title,
                    status: row.status,
                    category: row.resolutionCategory,
                    effectiveness: row.effectiveness,
                    resolvedAtRaw: row.resolvedAt
                )
            }

        return ProjectResolutionFeedback(
            total: total,
            resolved: resolved,
            dismissed: dismissed,
            active: active,
            followUpRequired: followUpRequired,
            dominantCategory: dominantCategory,
            reopenedCount: reopenedCount,
            recentResolutions: Array(recent)
        )
    }

    // MARK: - 2.6 Risk action sync write path foundation

    /// Decode shape for `profiles.select('org_id').eq('id', <auth.uid>).single()` — mirrors
    /// Web's `createRiskAction` at `BrainStorm+-Web/src/lib/actions/risk-actions.ts`
    /// lines 332-336. Kept private because `org_id` is consumed inline during the insert
    /// and discarded; the core `Profile` struct deliberately does not carry `org_id` so a
    /// session refresh doesn't need to know about this foundation.
    private struct ProfileOrgRow: Decodable {
        let orgId: UUID
        enum CodingKeys: String, CodingKey { case orgId = "org_id" }
    }

    /// Insert shape for `risk_actions`. Column selection mirrors Web's `createRiskAction`
    /// exactly (lines 340-352): `org_id, risk_type, source_type, source_id, ai_source_id,
    /// title, detail, severity, suggested_action, status, created_by`. Every field is
    /// populated on the client — none of them require server-only enrichment, which is why
    /// Path A (direct Supabase insert) is safe here.
    ///
    /// Web defaults `riskType` to `'manual'` when `type` is absent and `severity` to
    /// `'medium'` when caller omits it; iOS always passes both explicitly (the sync affords
    /// no picker, so `type` is hard-coded `'manual'` and `severity` is pre-mapped from the
    /// risk analysis's `RiskLevel`).
    ///
    /// `status` is hard-coded to `'open'` on insert — Web does the same (line 349) and the
    /// subsequent "2.5 write-back" foundations (close / reopen / effectiveness / governance
    /// note) are intentionally out of scope for 2.6.
    private struct RiskActionInsert: Encodable {
        let orgId: UUID
        let riskType: String
        let sourceType: String
        let sourceId: UUID?
        let aiSourceId: UUID?
        let title: String
        let detail: String?
        let severity: String
        let suggestedAction: String?
        let status: String
        let createdBy: UUID

        enum CodingKeys: String, CodingKey {
            case orgId = "org_id"
            case riskType = "risk_type"
            case sourceType = "source_type"
            case sourceId = "source_id"
            case aiSourceId = "ai_source_id"
            case title
            case detail
            case severity
            case suggestedAction = "suggested_action"
            case status
            case createdBy = "created_by"
        }
    }

    /// Decode shape for the `.select("id").single()` returned by the insert — we only need
    /// the new row's primary key so we can populate `lastSyncedRiskActionId` and (later)
    /// target it in the refreshed `linkedRiskActions` list.
    private struct RiskActionInsertResult: Decodable {
        let id: UUID
    }

    /// Insert shape for `risk_action_events`. Web's `createRiskAction` logs a best-effort
    /// audit event (lines 357-363) using `logRiskEvent(...)`; iOS mirrors the primary
    /// columns the Web helper writes: `action_id`, `event_type: 'created'`, `to_status:
    /// 'open'`, `actor_id`. `from_status` and `note` are omitted — Web also omits them for
    /// the initial create.
    ///
    /// This insert is "best effort": failures are swallowed so the primary `risk_actions`
    /// insert still reports success. Audit history is useful but not load-bearing for the
    /// sync affordance, and mirroring Web's resilience here keeps iOS parity tight.
    private struct RiskActionEventInsert: Encodable {
        let actionId: UUID
        let eventType: String
        let toStatus: String
        let actorId: UUID

        enum CodingKeys: String, CodingKey {
            case actionId = "action_id"
            case eventType = "event_type"
            case toStatus = "to_status"
            case actorId = "actor_id"
        }
    }

    /// Maps the iOS `ProjectRiskAnalysis.RiskLevel` enum into the three-value `severity`
    /// vocabulary Web's risk-action insert accepts. Mirrors the ternary at
    /// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 692-695:
    ///
    /// ```tsx
    /// riskLevel === 'critical' || riskLevel === 'high'
    ///   ? 'high'
    ///   : riskLevel === 'medium' ? 'medium' : 'low'
    /// ```
    ///
    /// Adds one iOS-specific branch for `.unknown`: Web never constructs the button with an
    /// unknown level (the analysis state has already normalized it), so the mapping is not
    /// defined server-side. iOS chooses `'medium'` for unknown — the neutral default in the
    /// `risk_actions` schema — rather than silently tagging the row `low` (understates
    /// risk) or `high` (overstates).
    private static func mapRiskLevelToSeverity(_ level: ProjectRiskAnalysis.RiskLevel) -> String {
        switch level {
        case .critical, .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        case .unknown: return "medium"
        }
    }

    /// Builds the user-facing preview payload shown inside the confirmation dialog, OR
    /// returns `nil` when the project row / risk analysis is missing (either means there is
    /// no valid input for the insert). Deterministic — mirrors the exact field shape Web's
    /// `handleSyncToRiskAction` constructs at lines 687-697 of the web dashboard page.
    ///
    /// `detail` is sliced to the first 200 characters of the raw risk summary to match
    /// Web's `.slice(0, 200)`. The slice is measured on Swift's String character count,
    /// which is grapheme-cluster-safe (unlike the JS `.slice` on UTF-16 code units); the
    /// difference only matters for emoji / combining marks and will never truncate mid-
    /// codepoint. Web's 200-unit cap is a soft UX bound, not a persistence constraint, so
    /// the cluster-safe slice stays in source-of-truth parity.
    public func riskActionSyncDraft() -> RiskActionSyncDraft? {
        guard let project, let analysis = riskAnalysis else { return nil }

        let rawSummary = analysis.summary
        let detailSlice = String(rawSummary.prefix(200))
        let severity = Self.mapRiskLevelToSeverity(analysis.riskLevel)

        return RiskActionSyncDraft(
            title: "[\(project.name)] 风险项",
            detail: detailSlice,
            severity: severity
        )
    }

    /// The write path itself. Mirrors Web's `syncRiskFromDetection → createRiskAction` flow
    /// end-to-end without introducing any server-only dependency.
    ///
    /// **Preconditions** (all enforced here, not by UI alone):
    /// 1. `rawRole` passes `RBACManager.shared.canManageRiskActions(rawRole:)` —
    ///    client-side mirror of DB RLS policies for `risk_actions` (migrations
    ///    014 + 037: `['super_admin', 'admin', 'hr_admin', 'manager']`, with
    ///    canonical `superadmin` alias added for Phase 2). Intentionally narrower
    ///    than Web's `serverGuard({ requiredRole: 'manager' })` (which admits 6
    ///    roles at level ≥ 2); RLS is the authoritative write-time gate either
    ///    way. Failing this sets `riskActionSyncErrorMessage` and returns false
    ///    without contacting Supabase.
    /// 2. `project != nil && riskAnalysis != nil` — the confirmation dialog cannot render
    ///    without these, but we re-check at the top of the method so a race between the
    ///    user tapping "Convert" and a concurrent `applyDeniedState()` can't corrupt state.
    /// 3. `project_risk_summaries` has an anchor row for this project. iOS does NOT cache
    ///    the anchor id from the 2.4 / 2.5 reads, so it re-fetches here for freshness and
    ///    to isolate this flow from prior section state. One extra round-trip is cheap and
    ///    matches the "self-contained operation" posture the 2.4 / 2.5 reads already use.
    /// 4. The session has a resolved `auth.uid` AND that profile carries an `org_id` — Web
    ///    requires both and iOS must not paper over either. Missing either → failure with a
    ///    scoped error; no insert is attempted.
    ///
    /// **Insert payload** is built verbatim from `riskActionSyncDraft()` + the fetched
    /// anchor id + the auth user's `org_id` + the auth user's `id`. `risk_type`, `status`,
    /// and `suggested_action` are hard-coded to Web's call-site values: `'manual'`,
    /// `'open'`, `'从项目风险分析生成'`. `sourceType` is `'project'`, `sourceId` is
    /// `project.id`. Every other field is either UI-driven or auth-derived.
    ///
    /// **Post-success effects** (devprompt §3.D):
    /// - `lastSyncedRiskActionId` holds the newly-inserted row id so the view / future
    ///   rounds can target it.
    /// - `refreshLinkedRiskActions()` and `refreshResolutionFeedback()` are dispatched in
    ///   parallel so both snapshots catch up. Neither is awaited by this method — they run
    ///   as their own isolated flows and set their own phases / error messages.
    /// - `riskActionSyncPhase` flips to `.succeeded`; the View's side-effect schedules the
    ///   3-second auto-clear back to `.idle`. Web's `setTimeout(() => setSyncMsg(null),
    ///   3000)` at line 221 of the web dashboard is mirrored there, not here.
    ///
    /// **Failure posture** mirrors the 2.4 / 2.5 "preserve prior snapshot" rule:
    /// - Only `riskActionSyncErrorMessage` is written.
    /// - `riskActionSyncPhase` reverts to `.idle` (not `.failed` — there's no failed phase;
    ///   the scoped error alone communicates failure, consistent with how the linked-
    ///   actions / resolution-feedback read flows treat transient failure).
    /// - `lastSyncedRiskActionId` is NOT cleared — a successful prior sync in the same
    ///   detail instance stays discoverable.
    /// - No other error surface is touched.
    ///
    /// Returns `true` on successful insert (even if the best-effort event log fails),
    /// `false` on every failure path. The caller decides what to render on `false`; this
    /// VM writes the scoped error and leaves the view in the reverted phase.
    public func syncRiskActionFromDetail(rawRole: String?) async -> Bool {
        // 1. RBAC gate. Mirrors Web's server guard before any Supabase contact.
        guard RBACManager.shared.canManageRiskActions(rawRole: rawRole) else {
            self.riskActionSyncErrorMessage = "Converting a risk into a risk action requires admin or manager privileges."
            return false
        }

        // 2. Precondition re-check — survives races with applyDeniedState().
        guard let project, let analysis = riskAnalysis else {
            self.riskActionSyncErrorMessage = "Risk analysis is not available for this project."
            return false
        }

        // Draft is the confirmation-dialog payload — title / detail / severity. Rebuilding
        // here (rather than taking it as a parameter) keeps the VM authoritative — a caller
        // that somehow holds a stale draft cannot poison the insert.
        let draft = RiskActionSyncDraft(
            title: "[\(project.name)] 风险项",
            detail: String(analysis.summary.prefix(200)),
            severity: Self.mapRiskLevelToSeverity(analysis.riskLevel)
        )

        // Empty-title defense. Web's `createRiskAction` trims + rejects at line 327; iOS
        // matches that shape even though the draft is a template string (the user might
        // encounter an unnamed project in some edge seed).
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            self.riskActionSyncErrorMessage = "Cannot sync: risk action title is empty."
            return false
        }

        riskActionSyncPhase = .syncing
        riskActionSyncErrorMessage = nil

        do {
            // 3. Re-fetch anchor (project_risk_summaries.id for this project). Parity with
            //    Web's sync flow, which also re-reads the anchor each call.
            let anchorRows: [LinkedRiskAnchorRow] = try await client
                .from("project_risk_summaries")
                .select("id")
                .eq("project_id", value: projectId)
                .limit(1)
                .execute()
                .value

            guard let anchor = anchorRows.first else {
                self.riskActionSyncErrorMessage = "No risk analysis exists for this project yet. Generate one on the web first."
                self.riskActionSyncPhase = .idle
                return false
            }

            // 4. Resolve auth user + org. Web's createRiskAction does both at lines 322-336.
            let user = try await client.auth.session.user
            let orgRows: [ProfileOrgRow] = try await client
                .from("profiles")
                .select("org_id")
                .eq("id", value: user.id)
                .limit(1)
                .execute()
                .value

            guard let org = orgRows.first else {
                self.riskActionSyncErrorMessage = "Unable to resolve your organization. Please re-sign in and try again."
                self.riskActionSyncPhase = .idle
                return false
            }

            // 5. Primary insert → risk_actions.
            let insertPayload = RiskActionInsert(
                orgId: org.orgId,
                riskType: "manual",
                sourceType: "project",
                sourceId: project.id,
                aiSourceId: anchor.id,
                title: trimmedTitle,
                detail: draft.detail.isEmpty ? nil : draft.detail,
                severity: draft.severity,
                suggestedAction: "从项目风险分析生成",
                status: "open",
                createdBy: user.id
            )

            let inserted: RiskActionInsertResult = try await client
                .from("risk_actions")
                .insert(insertPayload)
                .select("id")
                .single()
                .execute()
                .value

            // 6. Best-effort audit log. Mirrors Web's `logRiskEvent` behavior: failure
            //    here does NOT invalidate the primary insert — we swallow and move on.
            do {
                let eventPayload = RiskActionEventInsert(
                    actionId: inserted.id,
                    eventType: "created",
                    toStatus: "open",
                    actorId: user.id
                )
                try await client
                    .from("risk_action_events")
                    .insert(eventPayload)
                    .execute()
            } catch {
                // Intentional swallow — audit event failure does not block the sync.
            }

            // 7. Commit success state; dispatch post-write refreshes in parallel. Neither
            //    refresh is awaited — they run as their own isolated flows, touch their
            //    own error surfaces, and should not block the success hint from showing.
            self.lastSyncedRiskActionId = inserted.id
            self.riskActionSyncPhase = .succeeded

            Task { [weak self] in
                await self?.refreshLinkedRiskActions()
            }
            Task { [weak self] in
                await self?.refreshResolutionFeedback()
            }

            return true
        } catch {
            self.riskActionSyncErrorMessage = ErrorLocalizer.localize(error)
            self.riskActionSyncPhase = .idle
            return false
        }
    }

    /// Called by the View 3 seconds after a `.succeeded` sync to clear the success hint and
    /// return the affordance to `.idle`. Mirrors Web's `setTimeout(() => setSyncMsg(null),
    /// 3000)` at `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` line 221. Kept on
    /// the VM rather than the View so the timer's side-effect is observable in the same
    /// @Published property the View already binds to.
    ///
    /// Only clears when the current phase is still `.succeeded` — if a new sync started
    /// meanwhile (flipping phase back to `.syncing`) we leave it alone so the pending
    /// write-in-flight state isn't stomped. `lastSyncedRiskActionId` is preserved across
    /// the auto-clear so downstream UI can keep targeting the freshly-synced row in
    /// `linkedRiskActions`.
    public func clearRiskActionSyncSuccess() {
        guard riskActionSyncPhase == .succeeded else { return }
        riskActionSyncPhase = .idle
    }
}
