import SwiftUI
import Supabase

/// Read-only detail view for a single objective. Web doesn't have a
/// dedicated detail route; this surfaces the same fields that Web's
/// expanded accordion row reveals (title, description, status, assignee,
/// owner, KR list with progress, computed objective progress).
public struct OKRDetailView: View {
    @StateObject private var viewModel: OKRDetailViewModel

    public init(viewModel: OKRDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                headerCard
                progressCard
                ownerCard
                keyResultsCard
                if let msg = viewModel.errorMessage {
                    Text(msg)
                        .font(BsTypography.inter(12, weight: "Regular"))
                        .foregroundColor(BsColor.danger)
                }
                Spacer(minLength: BsSpacing.xl)
            }
            .padding(.horizontal, BsSpacing.lg + 4)
            .padding(.top, BsSpacing.md)
        }
        .background(BsColor.surfaceSecondary.ignoresSafeArea())
        .navigationTitle("目标详情")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Header (title + status + period)

    private var headerCard: some View {
        let obj = viewModel.objective
        return VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            HStack(spacing: BsSpacing.sm) {
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [BsColor.brandAzure, BsColor.brandMint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.title)
                        .font(BsTypography.outfit(18, weight: "Bold"))
                        .foregroundColor(BsColor.ink)
                    HStack(spacing: 6) {
                        statusBadge(obj.status)
                        if let period = obj.period {
                            Text(period)
                                .font(BsTypography.inter(10, weight: "SemiBold"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BsColor.brandAzure.opacity(0.08))
                                .foregroundColor(BsColor.brandAzure)
                                .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs))
                        }
                    }
                }
                Spacer()
            }
            if let desc = obj.description, !desc.isEmpty {
                Divider().background(BsColor.borderSubtle)
                Text(desc)
                    .font(BsTypography.inter(13, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Progress

    private var progressCard: some View {
        let pct = viewModel.objective.computedProgress
        return VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            HStack {
                Text("进度")
                    .font(BsTypography.inter(11, weight: "Bold"))
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(pct)%")
                    .font(BsTypography.outfit(20, weight: "Bold"))
                    .foregroundColor(progressColor(pct))
            }
            progressBar(progress: pct, height: 10)
            Text(progressNote(pct))
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func progressNote(_ pct: Int) -> String {
        let krs = viewModel.objective.keyResults ?? []
        let count = krs.count
        if count == 0 { return "尚未添加关键结果" }
        return "基于 \(count) 个关键结果的平均进度"
    }

    // MARK: - Owner + Assignee

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            Text("负责人")
                .font(BsTypography.inter(11, weight: "Bold"))
                .foregroundColor(BsColor.inkMuted)
                .textCase(.uppercase)

            if viewModel.owner == nil && viewModel.assignee == nil {
                Text("未指定")
                    .font(BsTypography.inter(12, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let owner = viewModel.owner {
                        personRow(label: "Owner", profile: owner)
                    }
                    if let assignee = viewModel.assignee,
                       assignee.id != viewModel.owner?.id {
                        personRow(label: "负责执行", profile: assignee)
                    }
                }
            }
        }
        .padding(BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func personRow(label: String, profile: Profile) -> some View {
        HStack(spacing: BsSpacing.md - 2) {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .overlay(
                    Text(String((profile.fullName ?? profile.displayName ?? "?").prefix(1)))
                        .font(BsTypography.inter(12, weight: "Bold"))
                        .foregroundColor(BsColor.brandAzure)
                )
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName ?? profile.displayName ?? "未命名")
                    .font(BsTypography.inter(13, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Text(label)
                    .font(BsTypography.inter(10, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
            }
            Spacer()
            if let dept = profile.department, !dept.isEmpty {
                Text(dept)
                    .font(BsTypography.inter(10, weight: "Medium"))
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 3)
                    .background(BsColor.brandMint.opacity(0.15))
                    .foregroundColor(BsColor.inkMuted)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Key Results

    private var keyResultsCard: some View {
        let krs = viewModel.objective.keyResults ?? []
        return VStack(alignment: .leading, spacing: BsSpacing.md) {
            HStack {
                Text("关键结果")
                    .font(BsTypography.inter(11, weight: "Bold"))
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("共 \(krs.count) 项")
                    .font(BsTypography.inter(11, weight: "SemiBold"))
                    .foregroundColor(BsColor.inkMuted)
            }

            if krs.isEmpty {
                Text("暂无关键结果")
                    .font(BsTypography.inter(12, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
            } else {
                VStack(spacing: BsSpacing.md - 2) {
                    ForEach(krs) { kr in
                        krDetailRow(kr)
                    }
                }
            }
        }
        .padding(BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func krDetailRow(_ kr: KeyResult) -> some View {
        let pct = kr.progressPercent
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kr.title)
                    .font(BsTypography.inter(13, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                Text("\(pct)%")
                    .font(BsTypography.outfit(13, weight: "Bold"))
                    .foregroundColor(progressColor(pct))
            }
            progressBar(progress: pct, height: 6)
            HStack {
                Text("当前 \(formatNumeric(kr.currentValue))\(kr.unit.map { " \($0)" } ?? "")")
                    .font(BsTypography.inter(10, weight: "Medium"))
                    .foregroundColor(BsColor.inkMuted)
                Spacer()
                Text("目标 \(formatNumeric(kr.targetValue))\(kr.unit.map { " \($0)" } ?? "")")
                    .font(BsTypography.inter(10, weight: "Medium"))
                    .foregroundColor(BsColor.inkMuted)
            }
        }
        .padding(BsSpacing.md)
        .background(BsColor.surfaceSecondary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }

    // MARK: - Formatting + shared helpers (duplicated from OKRListView
    //         intentionally — keeps each view self-contained; refactor
    //         to a shared OKRStyle helper when a third view needs them.)

    private func formatNumeric(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }

    private func statusBadge(_ status: Objective.ObjectiveStatus) -> some View {
        let (bg, fg) = statusColors(status)
        return Text(status.displayLabel)
            .font(BsTypography.inter(9, weight: "Bold"))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(fg)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs))
    }

    private func statusColors(_ status: Objective.ObjectiveStatus) -> (Color, Color) {
        switch status {
        case .draft:
            return (BsColor.inkFaint.opacity(0.2), BsColor.inkMuted)
        case .active:
            return (BsColor.brandAzure.opacity(0.1), BsColor.brandAzure)
        case .completed:
            return (BsColor.success.opacity(0.1), BsColor.success)
        case .cancelled:
            return (BsColor.danger.opacity(0.1), BsColor.danger)
        }
    }

    private func progressBar(progress: Int, height: CGFloat) -> some View {
        let clamped = max(0, min(progress, 100))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BsColor.inkFaint.opacity(0.25))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: progressGradient(progress: clamped),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * CGFloat(clamped) / 100)
            }
        }
        .frame(height: height)
    }

    private func progressColor(_ p: Int) -> Color {
        if p >= 70 { return BsColor.success }
        if p >= 40 { return BsColor.warning }
        return BsColor.brandAzure
    }

    private func progressGradient(progress p: Int) -> [Color] {
        if p >= 70 {
            return [BsColor.success.opacity(0.85), BsColor.success]
        }
        if p >= 40 {
            return [BsColor.warning.opacity(0.85), BsColor.warning]
        }
        return [BsColor.brandAzure.opacity(0.85), BsColor.brandAzure]
    }
}
