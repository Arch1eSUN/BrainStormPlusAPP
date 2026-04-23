import SwiftUI

/// Schedule root view.
///
/// Batch C.3 — multi-view mode mirroring Web
/// `src/app/dashboard/schedules/` (4 modes: `timeline` / `calendar` /
/// `list` / `my`). Employee-facing ports first; timeline + calendar
/// surface a "即将推出" placeholder because the Web versions lean on
/// heavy chrome (grid virtualization + department joins) that's deferred.
///
/// Shared model: the `ScheduleViewModel` in-VM cache (`states` map keyed
/// by YYYY-MM-DD) backs every mode. Pull-to-refresh invalidates and
/// re-fetches; mode switches don't refetch — they just re-read the cache.
public struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    @Namespace private var topAnimation

    // Horizontal date strip dates — unchanged from the original view,
    // kept for the "today card" mode. `-3…+7` around today.
    @State private var stripDates: [Date] = []

    // Quick-apply sheet state (from "my" view rows).
    @State private var quickApply: QuickApplyRoute?

    public init() {}

    private func setupStripDates() {
        let calendar = Calendar.current
        let today = Date()
        for i in -3...7 {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                stripDates.append(date)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                BsAmbientBackground()

                VStack(spacing: 0) {
                    headerSection
                        .zIndex(10)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: BsSpacing.xl) {
                            switch viewModel.viewMode {
                            case .my:
                                myModeSection
                            case .list:
                                listModeSection
                            case .timeline, .calendar:
                                stubModeSection(for: viewModel.viewMode)
                            }
                        }
                        .padding(.top, BsSpacing.xl)
                        .padding(.horizontal, BsSpacing.xl)
                        .padding(.bottom, 120) // safe space for tabbar
                    }
                    .refreshable {
                        Haptic.soft()
                        await viewModel.refresh()
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $quickApply) { route in
                quickApplySheet(for: route)
            }
        }
        .onAppear {
            if stripDates.isEmpty { setupStripDates() }
        }
        .task {
            // Web behavior: employees default-land on "my" (see page.tsx:52-56).
            // iOS already defaults to `.my` on VM init; we simply load the
            // 14-day range the "my" view needs. All modes share this cache.
            await viewModel.loadMyRange()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BsSpacing.lg) {
            HStack {
                Text("日程")
                    .font(BsTypography.brandDisplay)
                    .foregroundStyle(BsColor.ink)
                Spacer()

                // Jump to Today
                Button(action: {
                    Haptic.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectedDate = Date()
                    }
                }) {
                    Text("今天")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, BsSpacing.lg)
                        .padding(.vertical, BsSpacing.sm)
                        .background(BsColor.brandAzure)
                        .clipShape(Capsule())
                        .bsShadow(BsShadow.sm)
                }
                .buttonStyle(SquishyButtonStyle())
            }
            .padding(.horizontal, BsSpacing.xl)
            .padding(.top, BsSpacing.lg)

            // View-mode switcher — mirrors Web `ViewSwitcher`.
            viewModeSwitcher
                .padding(.horizontal, BsSpacing.xl)

            // Horizontal Date strip — retained only for modes that benefit
            // from a scrubbable "today context" (timeline/calendar stubs).
            // `my` + `list` render their own date chrome below.
            if viewModel.viewMode != .my && viewModel.viewMode != .list {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BsSpacing.md) {
                        ForEach(stripDates, id: \.self) { date in
                            datePill(for: date)
                        }
                    }
                    .padding(.horizontal, BsSpacing.xl)
                    .padding(.bottom, BsSpacing.lg)
                }
            } else {
                Spacer().frame(height: BsSpacing.sm)
            }
        }
        .background(BsColor.surfaceSecondary.opacity(0.95))
        .background(.ultraThinMaterial)
    }

    private var viewModeSwitcher: some View {
        HStack(spacing: BsSpacing.xs + 2) {
            ForEach(ScheduleViewMode.allCases) { mode in
                viewModePill(mode)
            }
        }
        .padding(BsSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.lg - 2, style: .continuous)
                .fill(BsColor.surfacePrimary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg - 2, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 1)
        )
    }

    private func viewModePill(_ mode: ScheduleViewMode) -> some View {
        let isActive = viewModel.viewMode == mode
        return Button {
            Haptic.light()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.viewMode = mode
            }
        } label: {
            HStack(spacing: BsSpacing.xs) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(mode.displayLabel)
                    .font(BsTypography.captionSmall)
            }
            .foregroundStyle(isActive ? Color.white : BsColor.inkMuted)
            .padding(.horizontal, BsSpacing.md)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                            .fill(BsColor.brandAzure)
                            .matchedGeometryEffect(id: "viewModeBg", in: topAnimation)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func datePill(for date: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)

        let dfDay = DateFormatter()
        dfDay.dateFormat = "EEE"
        let dayStr = dfDay.string(from: date).uppercased()

        let dfNum = DateFormatter()
        dfNum.dateFormat = "d"
        let numStr = dfNum.string(from: date)

        return Button(action: {
            Haptic.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedDate = date
            }
        }) {
            VStack(spacing: BsSpacing.xs) {
                Text(dayStr)
                    .font(BsTypography.inter(10, weight: "Medium"))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : BsColor.inkMuted)

                Text(numStr)
                    .font(BsTypography.outfit(18, weight: "Bold"))
                    .foregroundStyle(isSelected ? Color.white : BsColor.ink)
            }
            .frame(width: 56, height: 72)
            .background {
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                            .fill(BsColor.brandAzure)
                            .bsShadow(BsShadow.md)

                        RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    }
                    .matchedGeometryEffect(id: "selectedDateBg", in: topAnimation)
                } else {
                    RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                        .fill(BsColor.surfacePrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                                .stroke(BsColor.borderSubtle, lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(SquishyButtonStyle())
    }

    // MARK: - My mode (14-day strip w/ quick-apply)

    @ViewBuilder
    private var myModeSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            // Keep the geofence attendance card at the top so "my" mode
            // remains the employee's home — matches today's iOS UX.
            AttendanceView()
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.xxl - 4, style: .continuous))
                .bsShadow(BsShadow.md)

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            Text("未来 14 天")
                .font(BsTypography.outfit(18, weight: "SemiBold"))
                .foregroundStyle(BsColor.ink)
                .padding(.top, BsSpacing.sm)

            // 14-day horizontal strip for quick day-jumping.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BsSpacing.sm) {
                    ForEach(viewModel.upcoming14Days, id: \.iso) { entry in
                        myStripChip(date: entry.date, iso: entry.iso)
                    }
                }
                .padding(.vertical, 2)
            }

            if viewModel.isLoading && viewModel.states.isEmpty {
                VStack(spacing: BsSpacing.sm) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                            .fill(BsColor.surfacePrimary)
                            .frame(height: 54)
                            .shimmer()
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: BsSpacing.sm) {
                        ForEach(viewModel.upcoming14Days, id: \.iso) { entry in
                            MyDayRow(
                                date: entry.date,
                                iso: entry.iso,
                                state: viewModel.states[entry.iso],
                                isSelected: Calendar.current.isDate(entry.date, inSameDayAs: viewModel.selectedDate),
                                onQuickApply: { kind in
                                    Haptic.light()
                                    quickApply = QuickApplyRoute(kind: kind, date: entry.date)
                                }
                            )
                            .id(entry.iso)
                        }
                    }
                    .onChange(of: viewModel.selectedDate) { _, newDate in
                        let iso = ScheduleViewModel.isoDateString(for: newDate)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(iso, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func myStripChip(date: Date, iso: String) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        let dowLabels = ["日", "一", "二", "三", "四", "五", "六"]
        let dow = Calendar.current.component(.weekday, from: date) - 1
        let dowStr = dowLabels[max(0, min(6, dow))]
        let dayStr = "\(Calendar.current.component(.day, from: date))"

        return Button {
            Haptic.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(dowStr)
                    .font(BsTypography.inter(10, weight: "Medium"))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : BsColor.inkMuted)
                Text(dayStr)
                    .font(BsTypography.outfit(15, weight: "SemiBold"))
                    .foregroundStyle(isSelected ? Color.white : BsColor.ink)
            }
            .frame(width: 42, height: 52)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .fill(isSelected ? BsColor.brandAzure : BsColor.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(SquishyButtonStyle())
    }

    // MARK: - List mode

    @ViewBuilder
    private var listModeSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            HStack {
                Text("未来 14 天 · 列表")
                    .font(BsTypography.outfit(18, weight: "SemiBold"))
                    .foregroundStyle(BsColor.ink)
                Spacer()
                Text(rangeSubtitle)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }

            if viewModel.isLoading && viewModel.states.isEmpty {
                VStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                            .fill(BsColor.surfacePrimary)
                            .frame(height: 36)
                            .shimmer()
                    }
                }
            } else {
                let sortedRows = viewModel.upcoming14Days
                    .compactMap { entry -> (date: Date, iso: String, state: DailyWorkState?)? in
                        (entry.date, entry.iso, viewModel.states[entry.iso])
                    }

                VStack(spacing: 0) {
                    listRowHeader
                    ForEach(sortedRows, id: \.iso) { row in
                        ListRow(date: row.date, iso: row.iso, state: row.state)
                        Divider().opacity(0.4)
                    }
                }
                .bsGlassCard(cornerRadius: BsRadius.lg)
            }
        }
    }

    private var listRowHeader: some View {
        HStack {
            Text("日期")
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 90, alignment: .leading)
            Text("状态")
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("时段")
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, BsSpacing.md + 2)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(BsColor.surfaceSecondary.opacity(0.6))
    }

    private var rangeSubtitle: String {
        guard let f = viewModel.rangeFrom, let t = viewModel.rangeTo else { return "—" }
        return "\(f) → \(t)"
    }

    // MARK: - Timeline / Calendar stubs

    @ViewBuilder
    private func stubModeSection(for mode: ScheduleViewMode) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            // Keep the today card context while the full chrome ships later.
            Text("今日状态")
                .font(BsTypography.outfit(18, weight: "SemiBold"))
                .foregroundStyle(BsColor.ink)

            if viewModel.isLoading && viewModel.selectedDayState == nil {
                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .fill(BsColor.surfacePrimary)
                    .frame(height: 100)
                    .shimmer()
            } else if let err = viewModel.errorMessage {
                errorBanner(err)
            } else if viewModel.selectedDayState == nil {
                emptyState
            } else {
                DayStateCardView(dws: viewModel.selectedDayState, date: viewModel.selectedDate)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            VStack(spacing: BsSpacing.md) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(BsColor.brandMint)
                Text("\(mode.displayLabel) 视图即将推出")
                    .font(BsTypography.outfit(16, weight: "Medium"))
                    .foregroundStyle(BsColor.ink)
                Text("稍后将支持团队层面的时间线 / 月视图。")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(BsSpacing.xl + 4)
            .bsGlassCard()
        }
    }

    // MARK: - Shared bits

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: BsSpacing.sm + 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BsColor.warning)
            Text(msg)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.ink)
                .lineLimit(2)
        }
        .padding(BsSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: BsSpacing.lg) {
            ZStack {
                Circle()
                    .fill(BsColor.brandMint.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(BsColor.brandMint)
            }

            Text("当天无排班记录")
                .font(BsTypography.outfit(16, weight: "Medium"))
                .foregroundStyle(BsColor.ink)

            Text("请联系管理员或等待 HR 排班")
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .bsGlassCard(cornerRadius: BsRadius.xxl - 4)
    }

    // MARK: - Quick-apply sheet wiring

    @ViewBuilder
    private func quickApplySheet(for route: QuickApplyRoute) -> some View {
        switch route.kind {
        case .leave:
            LeaveSubmitView(client: supabase, initialDate: route.date) { _ in
                // No VM refresh — Web doesn't refetch schedule on submit
                // either; the user sees the new row once the approval
                // flips to `approved` and daily_work_state repopulates.
            }
        case .fieldWork:
            FieldWorkSubmitView(client: supabase, initialDate: route.date) { _ in }
        case .businessTrip:
            BusinessTripSubmitView(client: supabase, initialDate: route.date) { _ in }
        }
    }
}

// MARK: - Quick-apply route (identifiable wrapper for .sheet(item:))

private struct QuickApplyRoute: Identifiable {
    enum Kind: String { case leave, fieldWork, businessTrip }
    let kind: Kind
    let date: Date
    var id: String { "\(kind.rawValue)-\(ScheduleViewModel.isoDateString(for: date))" }
}

// MARK: - My-view row

private struct MyDayRow: View {
    let date: Date
    let iso: String
    let state: DailyWorkState?
    var isSelected: Bool = false
    let onQuickApply: (QuickApplyRoute.Kind) -> Void

    private static let dowLabels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let stateStr = state?.state
        let color = WorkStateColors.color(state: stateStr, expectedStart: state?.expectedStart)
        let label = WorkStateLabels.label(state: stateStr, leaveType: state?.leaveType)

        HStack(spacing: BsSpacing.md + 2) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(dowLabel)
                    .font(BsTypography.inter(11, weight: "Medium"))
                    .foregroundStyle(BsColor.inkMuted)
                Text(dayLabel)
                    .font(BsTypography.outfit(15, weight: "SemiBold"))
                    .foregroundStyle(isToday ? BsColor.brandAzure : BsColor.ink)
            }
            .frame(width: 56, alignment: .leading)

            // State dot + label + shift window
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.ink)
                if let start = state?.expectedStart?.prefix(5),
                   let end = state?.expectedEnd?.prefix(5) {
                    Text("\(start) – \(end)")
                        .font(BsTypography.inter(11, weight: "Regular"))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quick-apply trio
            HStack(spacing: BsSpacing.xs) {
                quickApplyButton(icon: "calendar.badge.minus", tooltip: "请假", kind: .leave)
                quickApplyButton(icon: "figure.walk", tooltip: "外勤", kind: .fieldWork)
                quickApplyButton(icon: "briefcase.fill", tooltip: "出差", kind: .businessTrip)
            }
        }
        .padding(.horizontal, BsSpacing.md + 2)
        .padding(.vertical, BsSpacing.md - 1)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(isToday ? BsColor.brandAzure.opacity(0.06) : BsColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .stroke(isSelected ? BsColor.brandAzure.opacity(0.5) : BsColor.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private func quickApplyButton(icon: String, tooltip: String, kind: QuickApplyRoute.Kind) -> some View {
        Button {
            onQuickApply(kind)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(BsColor.surfaceSecondary.opacity(0.6))
                )
                .overlay(
                    Circle().stroke(BsColor.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
    }

    private var dowLabel: String {
        let dow = Calendar.current.component(.weekday, from: date) - 1
        return Self.dowLabels[max(0, min(6, dow))]
    }

    private var dayLabel: String {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return "\(m)/\(d)"
    }
}

// MARK: - List-view row

private struct ListRow: View {
    let date: Date
    let iso: String
    let state: DailyWorkState?

    var body: some View {
        let stateStr = state?.state
        let color = WorkStateColors.color(state: stateStr, expectedStart: state?.expectedStart)
        let label = WorkStateLabels.label(state: stateStr, leaveType: state?.leaveType)

        HStack {
            Text(iso)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(shiftLabel)
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, BsSpacing.md + 2)
        .padding(.vertical, BsSpacing.md)
    }

    private var shiftLabel: String {
        guard let start = state?.expectedStart?.prefix(5),
              let end = state?.expectedEnd?.prefix(5) else { return "—" }
        return "\(start) – \(end)"
    }
}
