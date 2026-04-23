import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Reporting CRUD aligned with Web semantics.
//
// Parity targets:
//   fetchDailyLogs / fetchTodayLog / saveDailyLog
//     → src/lib/actions/daily-logs.ts
//   fetchWeeklyReports / saveWeeklyReport
//     → src/lib/actions/weekly-reports.ts
//
// Key Web semantics we preserve:
//   • upsert on (user_id, date) — server unique constraint (migration 004)
//   • upsert on (user_id, week_start) — same migration
//   • content/summary trimmed, empty is rejected client-side
//   • approval_status is derived from approval_request_report join,
//     not a column. Historical rows (pre-2026-04-21) may have a row
//     there; new rows won't. We attempt the lookup and fail open.
//
// Web semantics deliberately NOT ported (yet):
//   • The Web saveDailyLog falls back to an admin client for org_id
//     when profiles.org_id is empty (creates one on the fly). On iOS
//     we rely on profiles.org_id being set server-side; if it's NULL
//     the upsert errors out and the user sees the banner.
//   • fetchDailyLogs does a sub-select on
//     `profiles:user_id(full_name,avatar_url)` + `projects:project_id(name)`.
//     iOS doesn't currently surface those join results in the list
//     UI, so we skip the sub-select to keep models flat.
//   • Web's `generateWeeklySummary` / `buildWeeklyContext` AI helpers
//     are P1 per the audit doc — deferred to a later batch.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ReportingViewModel: ObservableObject {
    public enum Tab: String, CaseIterable, Identifiable {
        case daily
        case weekly
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .daily: return "日报"
            case .weekly: return "周报"
            }
        }
    }

    @Published public var selectedTab: Tab = .daily
    @Published public private(set) var dailyLogs: [DailyLog] = []
    @Published public private(set) var weeklyReports: [WeeklyReport] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isSaving: Bool = false
    /// True while the weekly AI summary (Batch C.4a) is in flight. The
    /// edit sheet watches this to show a spinner on its "AI 生成摘要"
    /// button and disable interactions during the call.
    @Published public private(set) var isGeneratingAISummary: Bool = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ──────────────────────────────────────────────────────────────
    // Batch C.4a — AI weekly summary
    //
    // Web parity: src/lib/actions/summary-actions.ts ::
    //   generateWeeklySummary(weekStart).
    // Since that is a Next.js server action (cookie-auth), we cannot
    // call it directly from iOS. The Web side exposes a bearer-token
    // bridge at POST /api/mobile/ai/weekly-summary (mirrors the
    // api/mobile/attendance/clock pattern added in Batch A). Response
    // shape matches the server action:
    //     { summary: string; error: string | null }
    //
    // On success we fill the `summary` field; callers may also read
    // the returned text and populate `accomplishments` / other fields
    // from the Markdown sections if they want to, but the primary
    // surface mirrors Web's `setForm(f => ({ ...f, summary: res.summary }))`.
    // ──────────────────────────────────────────────────────────────

    public struct AISummaryResult {
        public let summary: String
        public let accomplishments: String?
    }

    private struct AISummaryResponse: Decodable {
        let summary: String?
        let error: String?
    }

    @discardableResult
    public func generateAIWeeklySummary(weekStart: Date) async -> AISummaryResult? {
        isGeneratingAISummary = true
        errorMessage = nil
        defer { isGeneratingAISummary = false }

        do {
            let session = try await client.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/ai/weekly-summary")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 45

            struct Body: Encodable { let week_start: String }
            let body = Body(week_start: isoDay(weekStart))
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "网络异常，请重试"
                return nil
            }

            let decoded = try? JSONDecoder().decode(AISummaryResponse.self, from: data)

            guard http.statusCode == 200 else {
                errorMessage = decoded?.error ?? "AI 总结失败（HTTP \(http.statusCode)）"
                return nil
            }

            if let err = decoded?.error, !err.isEmpty {
                errorMessage = err
                return nil
            }

            guard let summary = decoded?.summary, !summary.isEmpty else {
                errorMessage = "AI 未返回内容"
                return nil
            }

            // Best-effort section extraction. Web leaves the full
            // Markdown in `summary`; we keep that behaviour but also
            // try to lift "已完成 / 本周工作总结" bullets into
            // `accomplishments` as a convenience, matching the audit
            // doc's request that the AI button "fills summary /
            // accomplishments".
            let accomplishments = Self.extractAccomplishments(from: summary)
            return AISummaryResult(summary: summary, accomplishments: accomplishments)
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return nil
        }
    }

    /// Pulls bullets from the "本周工作总结" or "已完成" section of the
    /// AI-generated Markdown. Falls back to nil when no such section
    /// exists so the caller doesn't overwrite a user-typed value.
    private static func extractAccomplishments(from markdown: String) -> String? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inSection = false
        var collected: [String] = []
        let headerHints = ["本周工作总结", "已完成", "重点完成事项"]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                let headerBody = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                let matches = headerHints.contains(where: { headerBody.contains($0) })
                if matches {
                    inSection = true
                    continue
                } else if inSection {
                    break
                }
            }
            if inSection, trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                collected.append(String(trimmed.dropFirst(2)))
            }
        }
        guard !collected.isEmpty else { return nil }
        return collected.joined(separator: "\n")
    }

    // ──────────────────────────────────────────────────────────────
    // Fetch
    // ──────────────────────────────────────────────────────────────

    public func fetchReports() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            let uid = session.user.id

            async let fetchedLogs: [DailyLog] = client
                .from("daily_logs")
                .select()
                .eq("user_id", value: uid)
                .order("date", ascending: false)
                .limit(30)
                .execute()
                .value

            async let fetchedWeekly: [WeeklyReport] = client
                .from("weekly_reports")
                .select()
                .eq("user_id", value: uid)
                .order("week_start", ascending: false)
                .limit(12)
                .execute()
                .value

            self.dailyLogs = try await fetchedLogs
            self.weeklyReports = try await fetchedWeekly

            // Historical approval_status join — fail open (non-fatal).
            await hydrateApprovalStatus()
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Denormalises `approval_request_report` for the currently loaded
    /// daily logs + weekly reports. Historical rows only (new rows
    /// never enter this table — see audit doc §Reporting).
    private func hydrateApprovalStatus() async {
        async let dailyMap = fetchApprovalStatusMap(
            type: "daily_log",
            ids: dailyLogs.map { $0.id }
        )
        async let weeklyMap = fetchApprovalStatusMap(
            type: "weekly_report",
            ids: weeklyReports.map { $0.id }
        )

        let (dMap, wMap) = await (dailyMap, weeklyMap)

        if !dMap.isEmpty {
            dailyLogs = dailyLogs.map { log in
                var copy = log
                if let s = dMap[log.id] { copy.approvalStatus = s }
                return copy
            }
        }
        if !wMap.isEmpty {
            weeklyReports = weeklyReports.map { r in
                var copy = r
                if let s = wMap[r.id] { copy.approvalStatus = s }
                return copy
            }
        }
    }

    private func fetchApprovalStatusMap(
        type: String,
        ids: [UUID]
    ) async -> [UUID: ReportApprovalStatus] {
        guard !ids.isEmpty else { return [:] }
        struct Link: Decodable {
            let reportId: UUID
            let approvalRequests: NestedStatus?
            struct NestedStatus: Decodable { let status: String }
            enum CodingKeys: String, CodingKey {
                case reportId = "report_id"
                case approvalRequests = "approval_requests"
            }
        }
        do {
            let rows: [Link] = try await client
                .from("approval_request_report")
                .select("report_id, approval_requests(id, status)")
                .eq("report_type", value: type)
                .in("report_id", values: ids.map { $0.uuidString })
                .execute()
                .value
            return rows.reduce(into: [:]) { acc, row in
                guard let raw = row.approvalRequests?.status,
                      let status = ReportApprovalStatus(rawValue: raw) else { return }
                acc[row.reportId] = status
            }
        } catch {
            // Non-fatal — absence of the table or RLS denial just
            // means no historical badges render.
            return [:]
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Daily log CRUD
    // ──────────────────────────────────────────────────────────────

    private struct DailyLogUpsert: Encodable {
        let userId: String
        let orgId: String?
        let date: String
        let content: String
        let mood: String?
        let projectId: String?
        let taskIds: [String]
        let progress: String?
        let blockers: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case orgId = "org_id"
            case date
            case content
            case mood
            case projectId = "project_id"
            case taskIds = "task_ids"
            case progress
            case blockers
        }
    }

    /// 1:1 port of `saveDailyLog` from daily-logs.ts.
    /// Upserts on (user_id, date). Use this for both create and edit.
    @discardableResult
    public func saveLog(
        date: Date,
        content: String,
        mood: DailyLog.Mood?,
        projectId: UUID?,
        taskIds: [UUID],
        progress: String?,
        blockers: String?
    ) async -> DailyLog? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "日报内容不能为空"
            return nil
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let session = try await client.auth.session
            let uid = session.user.id
            let orgId = try await fetchCurrentOrgId(userId: uid)

            let payload = DailyLogUpsert(
                userId: uid.uuidString,
                orgId: orgId?.uuidString,
                date: isoDay(date),
                content: trimmed,
                mood: mood?.rawValue,
                projectId: projectId?.uuidString,
                taskIds: taskIds.map { $0.uuidString },
                progress: progress?.trimmedOrNil,
                blockers: blockers?.trimmedOrNil
            )

            let saved: DailyLog = try await client
                .from("daily_logs")
                .upsert(payload, onConflict: "user_id,date")
                .select()
                .single()
                .execute()
                .value

            // Local cache refresh: replace-or-prepend by date.
            if let idx = dailyLogs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: saved.date) }) {
                dailyLogs[idx] = saved
            } else {
                dailyLogs.insert(saved, at: 0)
            }
            successMessage = "日志已保存"
            return saved
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return nil
        }
    }

    /// Edit helper — Web has no separate updateDailyLog; upsert covers
    /// it. We expose this name so call sites can be explicit.
    @discardableResult
    public func updateLog(_ log: DailyLog) async -> DailyLog? {
        await saveLog(
            date: log.date,
            content: log.content,
            mood: log.mood,
            projectId: log.projectId,
            taskIds: log.taskIds,
            progress: log.progress,
            blockers: log.blockers
        )
    }

    public func deleteLog(_ log: DailyLog) async {
        errorMessage = nil
        do {
            _ = try await client
                .from("daily_logs")
                .delete()
                .eq("id", value: log.id.uuidString)
                .execute()
            dailyLogs.removeAll { $0.id == log.id }
            successMessage = "日志已删除"
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Weekly report CRUD
    // ──────────────────────────────────────────────────────────────

    private struct WeeklyReportUpsert: Encodable {
        let userId: String
        let orgId: String?
        let weekStart: String
        let weekEnd: String
        let summary: String
        let accomplishments: String?
        let plans: String?
        let blockers: String?
        let highlights: String?
        let challenges: String?
        let projectIds: [String]

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case orgId = "org_id"
            case weekStart = "week_start"
            case weekEnd = "week_end"
            case summary
            case accomplishments
            case plans
            case blockers
            case highlights
            case challenges
            case projectIds = "project_ids"
        }
    }

    /// 1:1 port of `saveWeeklyReport` from weekly-reports.ts.
    /// Upserts on (user_id, week_start).
    @discardableResult
    public func saveWeeklyReport(
        weekStart: Date,
        summary: String,
        accomplishments: String?,
        plans: String?,
        blockers: String?,
        highlights: String?,
        challenges: String?,
        projectIds: [UUID]
    ) async -> WeeklyReport? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "周报总结不能为空"
            return nil
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let session = try await client.auth.session
            let uid = session.user.id
            let orgId = try await fetchCurrentOrgId(userId: uid)

            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

            let payload = WeeklyReportUpsert(
                userId: uid.uuidString,
                orgId: orgId?.uuidString,
                weekStart: isoDay(weekStart),
                weekEnd: isoDay(weekEnd),
                summary: trimmed,
                accomplishments: accomplishments?.trimmedOrNil,
                plans: plans?.trimmedOrNil,
                blockers: blockers?.trimmedOrNil,
                highlights: highlights?.trimmedOrNil,
                challenges: challenges?.trimmedOrNil,
                projectIds: projectIds.map { $0.uuidString }
            )

            let saved: WeeklyReport = try await client
                .from("weekly_reports")
                .upsert(payload, onConflict: "user_id,week_start")
                .select()
                .single()
                .execute()
                .value

            if let idx = weeklyReports.firstIndex(where: {
                Calendar.current.isDate($0.weekStart, inSameDayAs: saved.weekStart)
            }) {
                weeklyReports[idx] = saved
            } else {
                weeklyReports.insert(saved, at: 0)
            }
            successMessage = "周报已保存"
            return saved
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return nil
        }
    }

    @discardableResult
    public func updateWeeklyReport(_ report: WeeklyReport) async -> WeeklyReport? {
        await saveWeeklyReport(
            weekStart: report.weekStart,
            summary: report.summary ?? "",
            accomplishments: report.accomplishments,
            plans: report.plans,
            blockers: report.blockers,
            highlights: report.highlights,
            challenges: report.challenges,
            projectIds: report.projectIds
        )
    }

    public func deleteWeeklyReport(_ report: WeeklyReport) async {
        errorMessage = nil
        do {
            _ = try await client
                .from("weekly_reports")
                .delete()
                .eq("id", value: report.id.uuidString)
                .execute()
            weeklyReports.removeAll { $0.id == report.id }
            successMessage = "周报已删除"
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    /// Matches the Web `getCurrentOrgId`: read profiles.org_id first,
    /// fall through to NULL if absent. Admin fallback intentionally
    /// omitted (see note at top of file).
    private func fetchCurrentOrgId(userId: UUID) async throws -> UUID? {
        struct Row: Decodable { let orgId: UUID?; enum CodingKeys: String, CodingKey { case orgId = "org_id" } }
        let rows: [Row] = try await client
            .from("profiles")
            .select("org_id")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.orgId
    }

    private func isoDay(_ date: Date) -> String {
        // Use the user's calendar, not UTC, to match Web which does
        // `new Date().toISOString().split('T')[0]` in local TZ on the
        // client form. Supabase DATE columns are timezone-agnostic.
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }
}

private extension String {
    /// Trim whitespace; return `nil` for empty. Mirrors Web's
    /// `form.x?.trim() || null` idiom used across the save actions.
    var trimmedOrNil: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
