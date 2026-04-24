import SwiftUI

// ══════════════════════════════════════════════════════════════════
// AdminEvaluationDetailView — 单条评估详情
// 替代 Web 的 detail-drawer.tsx：
//   - 顶部卡：姓名 / 部门 / 月份 / 总分 ring
//   - 风险标签 pills
//   - 人工复核提示 banner
//   - 叙述文本
//   - 五维进度条 + 数字
//   - 触发来源 + 模型 + 更新时间
// ══════════════════════════════════════════════════════════════════

public struct AdminEvaluationDetailView: View {
    public let row: MonthlyMatrixRow
    public let month: String

    public init(row: MonthlyMatrixRow, month: String) {
        self.row = row
        self.month = month
    }

    private struct Dimension: Identifiable {
        let id: String
        let label: String
        let score: Int?
    }

    private var dimensions: [Dimension] {
        let ev = row.evaluation
        return [
            Dimension(id: "attendance", label: "出勤", score: ev?.scoreAttendance),
            Dimension(id: "delivery", label: "交付", score: ev?.scoreDelivery),
            Dimension(id: "collaboration", label: "协作", score: ev?.scoreCollaboration),
            Dimension(id: "reporting", label: "汇报", score: ev?.scoreReporting),
            Dimension(id: "growth", label: "成长", score: ev?.scoreGrowth),
        ]
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if let ev = row.evaluation {
                    if ev.requiresManualReview { manualReviewBanner }
                    if let flags = ev.riskFlags, !flags.isEmpty { riskFlagsRow(flags) }
                    if let narrative = ev.narrative, !narrative.isEmpty {
                        narrativeCard(narrative)
                    }
                    dimensionsCard
                    metaCard(ev)
                } else {
                    notYetEvaluatedCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle(row.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // ── Header ─────────────────────────────────────────────────
    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ringScore(row.evaluation?.overallScore)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BsColor.ink)
                HStack(spacing: 6) {
                    Text(row.department ?? "未分部门")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                    Text("·")
                        .foregroundStyle(BsColor.inkFaint)
                    Text("\(month) 月评估")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if row.primaryRole == "superadmin" {
                    Text("超级管理员")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BsColor.brandAzure.opacity(0.15)))  // TODO(batch-3): evaluate .purple → brandAzure
                        .foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
                }
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BsColor.surfacePrimary))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
    }

    private func ringScore(_ score: Int?) -> some View {
        let value = Double(score ?? 0)
        let color = ringColor(score)
        return ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 6)
                .frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: min(max(value / 100.0, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 64, height: 64)
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                Text("总分")
                    .font(.system(.caption2))
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
    }

    private func ringColor(_ score: Int?) -> Color {
        guard let s = score else { return BsColor.inkMuted }
        if s >= 90 { return BsColor.success }
        if s >= 80 { return BsColor.brandAzure }
        if s >= 60 { return BsColor.warning }
        if s >= 40 { return BsColor.warning.opacity(0.85) }
        return BsColor.danger
    }

    // ── Manual review banner ───────────────────────────────────
    private var manualReviewBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BsColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("建议人工复核")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.warning)
                Text("数据不足或存在异常，奖金 / 调薪等决策请结合人工判断。")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BsColor.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BsColor.warning.opacity(0.3), lineWidth: 0.8))
    }

    // ── Risk flags ─────────────────────────────────────────────
    private func riskFlagsRow(_ flags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("风险标签")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
                .tracking(1)
            WrappingHStack(items: flags) { flag in
                Text(flag)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BsColor.warning.opacity(0.15)))
                    .foregroundStyle(BsColor.warning)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BsColor.surfacePrimary))
    }

    // ── Narrative ──────────────────────────────────────────────
    private func narrativeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("综合叙述")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
                .tracking(1)
            Text(text)
                .font(.body)
                .foregroundStyle(BsColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    // ── Dimensions ─────────────────────────────────────────────
    private var dimensionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("五维分数")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
                .tracking(1)
            VStack(spacing: 10) {
                ForEach(dimensions) { dim in
                    HStack(spacing: 10) {
                        Text(dim.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, alignment: .leading)
                            .foregroundStyle(BsColor.ink)
                        GeometryReader { geo in
                            let color = ringColor(dim.score)
                            let pct = Double(dim.score ?? 0) / 100.0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12))
                                RoundedRectangle(cornerRadius: 6).fill(color)
                                    .frame(width: max(0, geo.size.width * pct))
                            }
                        }
                        .frame(height: 8)
                        Text(dim.score.map(String.init) ?? "—")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, alignment: .trailing)
                            .foregroundStyle(ringColor(dim.score))
                    }
                }
            }
            Text("完整 evidence 明细请在 Web 端查看。")
                .font(.caption2)
                .foregroundStyle(BsColor.inkFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    // ── Meta ───────────────────────────────────────────────────
    private func metaCard(_ ev: MonthlyEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow(label: "触发来源", value: ev.triggeredBy == "manual" ? "手动评分" : (ev.triggeredBy == "cron" ? "月度自动评分" : "—"))
            metaRow(label: "模型", value: ev.modelUsed ?? "—")
            metaRow(label: "更新时间", value: formatDate(ev.updatedAt))
            metaRow(label: "创建时间", value: formatDate(ev.createdAt))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BsColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    // ── Not-yet-evaluated ──────────────────────────────────────
    private var notYetEvaluatedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(BsColor.brandAzure)
            Text("尚未评估")
                .font(.headline)
            Text("该员工 \(month) 月度评估尚未生成。批量任务目前在 Web 端触发。")
                .font(.footnote)
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }
}

// ── Wrapping HStack for risk flag pills ────────────────────────
private struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}
