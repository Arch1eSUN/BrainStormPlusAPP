import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// TeamMemberEvaluationPanel — 在 TeamMemberDetailView 里嵌入的"最近 6
// 个月 AI 评估"列表。Parity target: Web `dashboard/team/[userId]/page.tsx`
// 里的 EvaluationPanel。
//
// 权限闸门（View 侧）：
//   - viewer == self（自己看自己）
//   - viewer 拥有 ai_evaluation_access 能力包
//   - viewer primaryRole ∈ { admin, superadmin }
// 其它人不显示此面板。
//
// 数据源：public.user_monthly_evaluations，按 year_month desc 取前 6。
// NOTE: DB 字段是 `month`（TEXT YYYY-MM）、分数是 `overall_score`；
// 任务描述里的 `year_month`/`total_score` 字段名对齐 Web 命名语义，但
// iOS 端直接用 schema 字段（参考 MonthlyEvaluation.CodingKeys）。
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class TeamMemberEvaluationPanelViewModel: ObservableObject {
    @Published public private(set) var evaluations: [MonthlyEvaluation] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient
    private let userId: UUID

    public init(userId: UUID, client: SupabaseClient = supabase) {
        self.userId = userId
        self.client = client
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [MonthlyEvaluation] = try await client
                .from("user_monthly_evaluations")
                .select("id, user_id, month, overall_score, score_attendance, score_delivery, score_collaboration, score_reporting, score_growth, narrative, risk_flags, requires_manual_review, triggered_by, model_used, created_at, updated_at")
                .eq("user_id", value: userId.uuidString)
                .order("month", ascending: false)
                .limit(6)
                .execute()
                .value
            self.evaluations = rows
        } catch {
            self.errorMessage = "加载评估历史失败：\(ErrorLocalizer.localize(error))"
        }
    }
}

public struct TeamMemberEvaluationPanel: View {
    public let profile: Profile
    @StateObject private var vm: TeamMemberEvaluationPanelViewModel

    public init(profile: Profile) {
        self.profile = profile
        _vm = StateObject(wrappedValue: TeamMemberEvaluationPanelViewModel(userId: profile.id))
    }

    public var body: some View {
        BsCard(variant: .flat, padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundStyle(BsColor.brandAzure)
                    Text("最近 6 个月 AI 评估")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                    if vm.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }

                if vm.evaluations.isEmpty && !vm.isLoading {
                    HStack {
                        Spacer()
                        VStack(spacing: BsSpacing.xs) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(BsColor.inkFaint)
                            Text("暂无评估记录")
                                .font(BsTypography.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        .padding(.vertical, BsSpacing.lg)
                        Spacer()
                    }
                } else {
                    VStack(spacing: BsSpacing.sm) {
                        ForEach(vm.evaluations) { ev in
                            NavigationLink {
                                AdminEvaluationDetailView(
                                    row: matrixRow(for: ev),
                                    month: ev.month
                                )
                            } label: {
                                row(for: ev)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    // ── Row ────────────────────────────────────────────────────
    @ViewBuilder
    private func row(for ev: MonthlyEvaluation) -> some View {
        HStack(spacing: BsSpacing.md) {
            Text(ev.month)
                .font(BsTypography.cardSubtitle.monospacedDigit())
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(BsColor.ink)

            scoreBadge(ev.overallScore)

            Spacer()

            statusBadge(for: ev)

            Image(systemName: "chevron.right")
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkFaint)
        }
        .padding(.horizontal, BsSpacing.md)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                .fill(BsColor.surfaceSecondary)
        )
    }

    private func scoreBadge(_ score: Int?) -> some View {
        let text = score.map(String.init) ?? "—"
        let color: Color = {
            guard let s = score else { return BsColor.inkMuted }
            if s >= 90 { return BsColor.success }
            if s >= 80 { return BsColor.brandAzure }
            if s >= 60 { return BsColor.warning }
            return BsColor.danger
        }()
        return Text(text)
            .font(BsTypography.cardTitle.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: 46, alignment: .leading)
    }

    @ViewBuilder
    private func statusBadge(for ev: MonthlyEvaluation) -> some View {
        let (label, color): (String, Color) = {
            if ev.requiresManualReview { return ("需复核", BsColor.warning) }
            if ev.overallScore == nil { return ("待评", BsColor.inkMuted) }
            return ("已评", BsColor.success)
        }()
        Text(label)
            .font(BsTypography.captionSmall)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // ── Build a MonthlyMatrixRow wrapper so we can reuse
    // AdminEvaluationDetailView(row:month:) without changing its
    // signature. ──────────────────────────────────────────────
    private func matrixRow(for ev: MonthlyEvaluation) -> MonthlyMatrixRow {
        MonthlyMatrixRow(
            userId: profile.id,
            fullName: profile.fullName ?? "未命名",
            department: profile.department,
            primaryRole: primaryRoleString(profile.role),
            evaluation: ev
        )
    }

    private func primaryRoleString(_ raw: String?) -> String {
        switch raw {
        case "superadmin", "super_admin", "chairperson": return "superadmin"
        case "admin", "manager", "team_lead": return "admin"
        default: return "employee"
        }
    }
}
