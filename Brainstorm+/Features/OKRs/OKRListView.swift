import SwiftUI
import Supabase

/// Read-only OKR list ported from Web `BrainStorm+-Web/src/app/dashboard/okr/page.tsx`.
/// Shows a quarter/year picker, the 4-tile KPI stats cards, the overall
/// progress bar, and one row per objective with an expand affordance for
/// its key results. Tapping a row pushes the detail view.
public struct OKRListView: View {
    @StateObject private var viewModel: OKRListViewModel
    @State private var expanded: Set<UUID> = []
    @State private var showingCreate: Bool = false
    // Pending confirmation dialog state for status transitions / deletions.
    @State private var pendingStatus: PendingStatusChange? = nil
    @State private var pendingDelete: Objective? = nil
    @State private var actionError: String? = nil
    /// Bug-fix(滑动判定为点击 + 震动): NavigationLink in LazyVStack inside ScrollView
    /// 在 iOS 26 触发太敏感 —— 手指放上去稍微停留就触发 tap (NavigationLink push +
    /// contextMenu preview haptic),用户想滑动反馈成"点击"。
    /// 改用 Button + .navigationDestination(item:) 的程序化导航:Button 在
    /// ScrollView 里有正确的 tap-vs-drag 判定 (drag 超过阈值会自动 cancel tap)。
    @State private var pushTarget: Objective? = nil

    /// iOS 18+ zoom transition source namespace — Apple Photos / Maps
    /// tile→detail morph. Pair with `.matchedTransitionSource` + `.navigationTransition(.zoom)`.
    @Namespace private var zoomNamespace

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    /// Queued status-transition request waiting on user confirmation.
    private struct PendingStatusChange: Identifiable {
        let id = UUID()
        let objective: Objective
        let target: Objective.ObjectiveStatus
    }

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

            // Iter 7 §C.1 — skeleton-first via bsLoadingState。content view 在
            // loading/empty/error 状态下都保持挂载,设计系统 modifier 决定
            // chrome (redacted+shimmer / banner / ContentUnavailableView)。
            content
                .bsLoadingState(BsLoadingState.derive(
                    isLoading: viewModel.isLoading,
                    hasItems: !viewModel.objectives.isEmpty,
                    errorMessage: viewModel.errorMessage,
                    emptySystemImage: "target",
                    emptyTitle: "暂无 OKR",
                    emptyDescription: "切换到「+」新建一个目标，AI 会帮你拆 key results"
                ))
                .animation(.smooth(duration: 0.25), value: viewModel.objectives.count)
        }
        .navigationTitle("OKR 目标管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(.headline, weight: .semibold))
                }
                .tint(BsColor.brandAzure)
                .accessibilityLabel("新建 OKR")
            }
        }
        .sheet(isPresented: $showingCreate) {
            OKREditSheet(
                existing: nil,
                viewModel: viewModel,
                onDismiss: { showingCreate = false }
            )
            .bsSheetStyle(.form)
        }
        // Bug-fix(滑动判定为点击 + 震动): 程序化导航 destination,配合 list 内
        // Button + pushTarget binding,替代旧 NavigationLink 的过敏感 tap 触发。
        .navigationDestination(item: $pushTarget) { obj in
            OKRDetailView(
                viewModel: OKRDetailViewModel(client: supabase, initial: obj)
            )
            .navigationTransition(.zoom(sourceID: obj.id, in: zoomNamespace))
        }
        .confirmationDialog(
            pendingStatus.map { confirmStatusTitle($0) } ?? "",
            isPresented: Binding(
                get: { pendingStatus != nil },
                set: { if !$0 { pendingStatus = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStatus
        ) { change in
            Button(statusActionLabel(change.target)) {
                confirmStatusChange(change)
                pendingStatus = nil
            }
            Button("取消", role: .cancel) { pendingStatus = nil }
        }
        .confirmationDialog(
            "删除目标",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { obj in
            Button("删除", role: .destructive) {
                confirmDelete(obj)
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("删除后该目标及其 KR 无法恢复，确认？")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task(id: viewModel.period) {
            await viewModel.fetchObjectives()
        }
        .refreshable {
            await viewModel.fetchObjectives()
        }
    }

    private func confirmStatusTitle(_ change: PendingStatusChange) -> String {
        "确认\(statusActionLabel(change.target))？"
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
                            // Haptic removed: 用户反馈 picker 切换过密震动
                            viewModel.period = OKRListViewModel.formatPeriod(
                                year: year, quarter: parsed.quarter
                            )
                        }
                    }
                } label: {
                    HStack(spacing: BsSpacing.xs) {
                        Text(String(parsed.year))
                            .font(BsTypography.bodySmall.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(.caption2, weight: .bold))
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
                        // Haptic removed: 用户反馈 quarter 切换过密震动
                        viewModel.period = OKRListViewModel.formatPeriod(
                            year: parsed.year, quarter: q
                        )
                    } label: {
                        Text("Q\(q)")
                            .font(BsTypography.caption.weight(.bold))
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
                    .font(.system(.caption2))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(BsTypography.meta)
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(BsTypography.brandTitle)
                .foregroundColor(valueColor)
                .contentTransition(.numericText())
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
                    .font(BsTypography.label)
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(viewModel.overallProgress)%")
                    .font(BsTypography.sectionTitle.weight(.bold))
                    .foregroundColor(BsColor.ink)
                    .contentTransition(.numericText())
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
                    // Haptic removed: 用户反馈展开/收起辅助按钮过密震动
                    withAnimation(BsMotion.Anim.smooth) {
                        if isOpen { expanded.remove(obj.id) } else { expanded.insert(obj.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundColor(BsColor.inkMuted.opacity(0.8))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOpen ? "收起关键结果" : "展开关键结果")

                // Bug-fix(滑动判定为点击 + 震动): 用 Button + pushTarget 替代
                // NavigationLink。Button 在 ScrollView 里正确处理 tap-vs-drag。
                Button {
                    pushTarget = obj
                } label: {
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        HStack(spacing: 6) {
                            Text(obj.title)
                                .font(.system(.subheadline, weight: .bold))
                                .foregroundColor(BsColor.ink)
                                .lineLimit(1)
                            statusBadge(obj.status)
                        }
                        if let desc = obj.description, !desc.isEmpty {
                            Text(desc)
                                .font(BsTypography.captionSmall)
                                .foregroundColor(BsColor.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .matchedTransitionSource(id: obj.id, in: zoomNamespace)
                }
                .buttonStyle(.plain)

                // Progress pct + mini bar.
                VStack(alignment: .trailing, spacing: BsSpacing.xs) {
                    Text("\(pct)%")
                        .font(.system(.subheadline, weight: .bold))
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
                            .font(BsTypography.captionSmall)
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
        .contextMenu { objectiveContextMenu(obj) }
    }

    // MARK: - Context menu / confirmation flows for Objective rows

    @ViewBuilder
    private func objectiveContextMenu(_ obj: Objective) -> some View {
        let transitions = OKRListViewModel.validStatusTransitions[obj.status] ?? []
        ForEach(transitions, id: \.self) { target in
            Button {
                // Haptic removed: 用户反馈 contextMenu 选择过密震动；mutation 时再震
                pendingStatus = PendingStatusChange(objective: obj, target: target)
            } label: {
                Label(statusActionLabel(target), systemImage: statusActionIcon(target))
            }
        }
        if !transitions.isEmpty {
            Divider()
        }
        Button(role: .destructive) {
            // Haptic removed: 用户反馈菜单选择过密震动；真删确认时再震
            pendingDelete = obj
        } label: {
            Label("删除目标", systemImage: "trash")
        }
    }

    private func statusActionLabel(_ target: Objective.ObjectiveStatus) -> String {
        switch target {
        case .active: return "启用"
        case .completed: return "标记为已完成"
        case .cancelled: return "取消目标"
        case .draft: return "重开为草稿"
        }
    }

    private func statusActionIcon(_ target: Objective.ObjectiveStatus) -> String {
        switch target {
        case .active: return "play.fill"
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        case .draft: return "arrow.uturn.backward"
        }
    }

    private func confirmStatusChange(_ change: PendingStatusChange) {
        Task { @MainActor in
            do {
                try await viewModel.updateObjectiveStatus(
                    objectiveId: change.objective.id,
                    newStatus: change.target
                )
                // 仅 .completed 这种 terminal action 触发 haptic（按用户规则）
                if change.target == .completed {
                    Haptic.medium()
                }
            } catch {
                Haptic.warning()
                actionError = ErrorLocalizer.localize(error)
            }
        }
    }

    private func confirmDelete(_ obj: Objective) {
        Task { @MainActor in
            do {
                try await viewModel.deleteObjective(objectiveId: obj.id)
                Haptic.warning() // destructive 确认完成
            } catch {
                Haptic.warning()
                actionError = ErrorLocalizer.localize(error)
            }
        }
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
                    .font(BsTypography.meta)
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
            .font(BsTypography.meta)
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
                .font(.system(.largeTitle))
                .foregroundColor(BsColor.brandAzure.opacity(0.5))
            Text("暂无目标")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text("该季度尚未录入 OKR，点击右上角 + 新建一个。")
                .font(.system(.caption))
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
                .font(.system(.largeTitle))
                .foregroundColor(BsColor.warning)
            Text("加载失败")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text(message)
                .font(.system(.caption))
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xl)
            Button {
                Task { await viewModel.fetchObjectives() }
            } label: {
                Text("重试")
                    .font(BsTypography.bodySmall.weight(.semibold))
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
