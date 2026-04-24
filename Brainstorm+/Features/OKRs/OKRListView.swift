import SwiftUI
import Supabase

/// Read-only OKR list ported from Web `BrainStorm+-Web/src/app/dashboard/okr/page.tsx`.
/// Shows a quarter/year picker, the 4-tile KPI stats cards, the overall
/// progress bar, and one row per objective with an expand affordance for
/// its key results. Tapping a row pushes the detail view.
public struct OKRListView: View {
    @StateObject private var viewModel: OKRListViewModel
    @State private var expanded: Set<UUID> = []
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: OKRListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        ZStack {
            BsColor.surfaceSecondary.ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.objectives.isEmpty {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(BsColor.brandAzure)
                } else if let error = viewModel.errorMessage, viewModel.objectives.isEmpty {
                    errorState(message: error)
                } else {
                    content
                }
            }
        }
        .navigationTitle("OKR 目标管理")
        .navigationBarTitleDisplayMode(.large)
        .task(id: viewModel.period) {
            await viewModel.fetchObjectives()
        }
        .refreshable {
            await viewModel.fetchObjectives()
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: BsSpacing.lg) {
                periodPickerSection
                kpiStatsSection
                overallProgressSection

                if viewModel.objectives.isEmpty {
                    emptyState
                } else {
                    objectivesList
                }

                Spacer(minLength: BsSpacing.xl)
            }
            .padding(.horizontal, BsSpacing.lg + 4)
            .padding(.top, BsSpacing.sm)
        }
    }

    // MARK: - Period picker (year + quarter)

    private var periodPickerSection: some View {
        let parsed = OKRListViewModel.parsePeriod(viewModel.period)
            ?? (Calendar.current.component(.year, from: Date()), 1)

        return VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack {
                Text("季度")
                    .font(BsTypography.captionSmall)
                    .foregroundColor(BsColor.inkMuted)
                Spacer()
                // Year picker (Web hardcodes 2026; iOS allows ±1 year)
                Menu {
                    ForEach(viewModel.availableYears, id: \.self) { year in
                        Button(String(year)) {
                            viewModel.period = OKRListViewModel.formatPeriod(
                                year: year, quarter: parsed.quarter
                            )
                        }
                    }
                } label: {
                    HStack(spacing: BsSpacing.xs) {
                        Text(String(parsed.year))
                            .font(BsTypography.inter(13, weight: "SemiBold"))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(BsColor.brandAzure)
                    .padding(.horizontal, BsSpacing.md - 2)
                    .padding(.vertical, 6)
                    .background(BsColor.brandAzure.opacity(0.08))
                    .clipShape(Capsule())
                }
            }

            // Quarter pill tabs — mirrors Web `page.tsx:229-236`.
            HStack(spacing: 6) {
                ForEach(viewModel.availableQuarters, id: \.self) { q in
                    let active = parsed.quarter == q
                    Button {
                        viewModel.period = OKRListViewModel.formatPeriod(
                            year: parsed.year, quarter: q
                        )
                    } label: {
                        Text("Q\(q)")
                            .font(BsTypography.inter(12, weight: "Bold"))
                            .padding(.horizontal, BsSpacing.lg - 2)
                            .padding(.vertical, BsSpacing.sm)
                            .frame(maxWidth: .infinity)
                            .background(active ? BsColor.brandAzure : Color.clear)
                            .foregroundColor(active ? .white : BsColor.inkMuted)
                            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(BsSpacing.md + 2)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - KPI tiles

    private var kpiStatsSection: some View {
        let s = viewModel.stats
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            kpiTile(iconName: "target", iconColor: BsColor.brandAzure,
                    label: "目标总数", value: "\(s.totalObjectives)",
                    valueColor: BsColor.ink)
            kpiTile(iconName: "chart.bar.fill", iconColor: BsColor.warning,
                    label: "平均进度", value: "\(s.avgProgress)%",
                    valueColor: BsColor.ink)
            kpiTile(iconName: "checkmark.seal.fill", iconColor: BsColor.success,
                    label: "已完成", value: "\(s.completedCount)",
                    valueColor: BsColor.success)
            kpiTile(iconName: "exclamationmark.triangle.fill", iconColor: BsColor.danger,
                    label: "风险目标", value: "\(s.atRiskCount)",
                    valueColor: BsColor.danger)
        }
    }

    private func kpiTile(
        iconName: String, iconColor: Color,
        label: String, value: String, valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(BsTypography.inter(10, weight: "Bold"))
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(BsTypography.outfit(22, weight: "Bold"))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.md + 2)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Overall progress

    private var overallProgressSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack {
                Text("\(viewModel.period) 总体进度")
                    .font(BsTypography.inter(11, weight: "Bold"))
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(viewModel.overallProgress)%")
                    .font(BsTypography.outfit(16, weight: "Bold"))
                    .foregroundColor(BsColor.ink)
            }
            progressBar(progress: viewModel.overallProgress, height: 10)
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Objectives list (one row per objective)

    private var objectivesList: some View {
        LazyVStack(spacing: BsSpacing.md) {
            ForEach(viewModel.objectives) { obj in
                objectiveCard(obj)
            }
        }
    }

    private func objectiveCard(_ obj: Objective) -> some View {
        let isOpen = expanded.contains(obj.id)
        let pct = obj.computedProgress
        let isLocked = obj.status == .completed || obj.status == .cancelled

        return VStack(spacing: 0) {
            // Header row — tap chevron to expand, tap title area to push detail.
            HStack(spacing: BsSpacing.md) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isOpen { expanded.remove(obj.id) } else { expanded.insert(obj.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BsColor.inkMuted.opacity(0.8))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OKRDetailView(
                        viewModel: OKRDetailViewModel(client: supabase, initial: obj)
                    )
                } label: {
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        HStack(spacing: 6) {
                            Text(obj.title)
                                .font(BsTypography.inter(14, weight: "Bold"))
                                .foregroundColor(BsColor.ink)
                                .lineLimit(1)
                            statusBadge(obj.status)
                        }
                        if let desc = obj.description, !desc.isEmpty {
                            Text(desc)
                                .font(BsTypography.inter(11, weight: "Regular"))
                                .foregroundColor(BsColor.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // Progress pct + mini bar.
                VStack(alignment: .trailing, spacing: BsSpacing.xs) {
                    Text("\(pct)%")
                        .font(BsTypography.outfit(14, weight: "Bold"))
                        .foregroundColor(progressColor(pct))
                    progressBar(progress: pct, height: 4)
                        .frame(width: 72)
                }
            }
            .padding(BsSpacing.lg)
            .opacity(isLocked ? 0.75 : 1.0)

            // Expanded KR list.
            if isOpen {
                Divider().background(BsColor.borderSubtle)
                VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
                    let krs = obj.keyResults ?? []
                    if krs.isEmpty {
                        Text("暂无关键结果")
                            .font(BsTypography.inter(11, weight: "Regular"))
                            .foregroundColor(BsColor.inkMuted)
                    } else {
                        ForEach(krs) { kr in
                            krRow(kr)
                        }
                    }
                }
                .padding(BsSpacing.md + 2)
                .background(BsColor.surfaceSecondary.opacity(0.4))
            }
        }
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func krRow(_ kr: KeyResult) -> some View {
        let pct = kr.progressPercent
        return VStack(alignment: .leading, spacing: 6) {
            Text(kr.title)
                .font(BsTypography.captionSmall)
                .foregroundColor(BsColor.ink)
                .lineLimit(2)
            HStack(spacing: BsSpacing.sm) {
                progressBar(progress: pct, height: 4)
                Text(trailingFormatted(kr))
                    .font(BsTypography.inter(10, weight: "Bold"))
                    .foregroundColor(BsColor.inkMuted)
                    .monospacedDigit()
            }
        }
    }

    /// Mirrors Web `page.tsx:417` — e.g. `3/10 %` or `75/100 分`.
    private func trailingFormatted(_ kr: KeyResult) -> String {
        let current = formatNumeric(kr.currentValue)
        let target = formatNumeric(kr.targetValue)
        let unit = (kr.unit?.isEmpty == false) ? " \(kr.unit!)" : ""
        return "\(current)/\(target)\(unit)"
    }

    private func formatNumeric(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }

    // MARK: - Status badge

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

    // MARK: - Progress bar + color

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

    // MARK: - Empty + error

    private var emptyState: some View {
        VStack(spacing: BsSpacing.md) {
            Image(systemName: "target")
                .font(.system(size: 32))
                .foregroundColor(BsColor.brandAzure.opacity(0.5))
            Text("暂无目标")
                .font(BsTypography.outfit(16, weight: "SemiBold"))
                .foregroundColor(BsColor.ink)
            Text("该季度尚未录入 OKR，可在 Web 端创建。")
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BsSpacing.xxxl - 8)
        .padding(.horizontal, BsSpacing.xl)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BsSpacing.md - 2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(BsColor.warning)
            Text("加载失败")
                .font(BsTypography.outfit(16, weight: "SemiBold"))
                .foregroundColor(BsColor.ink)
            Text(message)
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xl)
            Button {
                Task { await viewModel.fetchObjectives() }
            } label: {
                Text("重试")
                    .font(BsTypography.inter(13, weight: "SemiBold"))
                    .padding(.horizontal, BsSpacing.xl - 2)
                    .padding(.vertical, BsSpacing.sm + 1)
                    .background(BsColor.brandAzure)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BsSpacing.xxxl - 8)
        .padding(.horizontal, BsSpacing.xl)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, BsSpacing.lg + 4)
    }
}
