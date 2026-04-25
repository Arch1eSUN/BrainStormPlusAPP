import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// AttendanceView — v2 (Iter6 §A.1 全面重构, 2026-04-25)
//
// ── 改动核心 ──────────────────────────────────────────────────────
// 用户反馈（CRITICAL）：
//   • 流体设计是 app 的设计语言（不是不喜欢液体动画）
//   • Dashboard 已经有 AttendanceHeroCard 那张液体打卡卡 —— 考勤页
//     不要再复刻一遍那张卡
//   • 但要保留"流体感觉"（其他形态：曲线 / 动态填充进度条等）
//   • app 内无需导出，但要显示**所有数据**：
//       - 当日 / 当周 / 当月 / 当年 segmented 切换
//       - 每天的状态：正常 / 请假 / 公休 / 外勤 / 出差 / 异常
//       - 详细 timeline（上下班时间 / 异常类型 / 备注）
//
// ── Layout（top → bottom）─────────────────────────────────────────
//   1. Segmented：本日 / 本周 / 本月 / 本年
//   2. AttendanceKPIRow：随 range 切换的大数字 + 多 stat tile
//   3. LiquidProgressBar：保留流体设计语言（横向流体填充进度条，
//      重用 LiquidFillShape 但水平布局，sin 曲线 60Hz 控制波纹）
//   4. AttendanceCalendarView：月历 / 年历 heat-map（month/year 视图）
//   5. AttendanceTimelineRow 列表（today/week 视图）
//   6. 异常修正 CTA：当 range 内有异常 → "申请补卡 / 修正异常" 按钮
// ══════════════════════════════════════════════════════════════════

public struct AttendanceView: View {
    @StateObject private var viewModel = AttendanceViewModel()
    @State private var selectedDay: AttendanceDay? = nil
    /// 长按"申请补卡 / 异常修正"目标日 —— 走 sheet(item:),非 nil 时弹
    /// AttendanceCorrectionSubmitSheet。
    @State private var fixTargetDay: AttendanceDay? = nil

    public let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
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
        ScrollView {
            VStack(spacing: BsSpacing.lg) {
                rangePicker
                kpiCard
                liquidProgressCard
                if viewModel.selectedRange == .month || viewModel.selectedRange == .year {
                    calendarCard
                }
                timelineCard
                if exceptionCount > 0 {
                    exceptionCTA
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.top, BsSpacing.md)
            .padding(.bottom, BsSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("考勤")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadToday()
            await viewModel.loadRange(viewModel.selectedRange)
        }
        .task(id: "attendance-load-v2") {
            await viewModel.loadToday()
            await viewModel.loadRange(viewModel.selectedRange)
        }
        .sheet(item: $selectedDay) { day in
            AttendanceDayDetailSheet(day: day)
                .bsSheetStyle(.detail)
        }
        .sheet(item: $fixTargetDay) { day in
            AttendanceCorrectionSubmitSheet(seed: day) {
                // 提交成功 → 重新拉本月范围,让用户立刻看到
                // pending 状态(后续 admin 审批后再回写 timeline)。
                Task { await viewModel.loadRange(viewModel.selectedRange) }
            }
            .bsSheetStyle(.form)
        }
    }

    // MARK: - Range picker (segmented)

    private var rangePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.selectedRange },
            set: { newValue in
                viewModel.setRange(newValue)
                Haptic.selection()
            }
        )) {
            ForEach(AttendanceRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - KPI card

    private var kpiCard: some View {
        BsContentCard(padding: .large) {
            AttendanceKPIRow(
                range: viewModel.selectedRange,
                days: rangeDaysSorted,
                today: todayDay
            )
        }
        .animation(.smooth(duration: 0.25), value: viewModel.selectedRange)
    }

    // MARK: - Liquid progress card (流体设计语言保留位)

    private var liquidProgressCard: some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progressTitle)
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                    Spacer(minLength: 0)
                    Text(progressSubtitle)
                        .font(BsTypography.captionSmall)
                        .monospacedDigit()
                        .foregroundStyle(BsColor.inkMuted)
                }

                LiquidProgressBar(progress: progressValue, tone: progressTone)
                    .frame(height: 28)
            }
        }
    }

    // MARK: - Calendar card (month / year heat-map)

    private var calendarCard: some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                BsSectionTitle(viewModel.selectedRange == .year ? "年度热力图" : "本月热力图", accent: .azure)

                AttendanceCalendarView(
                    range: viewModel.selectedRange,
                    days: viewModel.rangeDays,
                    rangeFromISO: viewModel.rangeFromISO,
                    rangeToISO: viewModel.rangeToISO,
                    onSelectDay: { day in
                        selectedDay = day
                    }
                )

                AttendanceCalendarLegend()
            }
        }
    }

    // MARK: - Timeline card (today / week list)

    private var timelineCard: some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                BsSectionTitle(timelineTitle, accent: .coral)

                let visible = visibleTimelineDays
                if visible.isEmpty {
                    Text("暂无数据")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                        .padding(.vertical, BsSpacing.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, day in
                            AttendanceTimelineRow(
                                day: day,
                                onDetail: { selectedDay = $0 },
                                onRequestFix: { d in
                                    fixTargetDay = d
                                }
                            )
                            if idx < visible.count - 1 {
                                Divider().background(BsColor.borderSubtle)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Exception CTA (bottom)

    private var exceptionCTA: some View {
        BsContentCard {
            HStack(spacing: BsSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(BsColor.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("有 \(exceptionCount) 条考勤异常")
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                    Text("可申请补卡或修正异常")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Spacer()
                Button {
                    Haptic.medium()
                    // 触发 sheet —— 第一条异常预填 target_date。
                    if let firstException = rangeDaysSorted.first(where: { $0.isException }) {
                        fixTargetDay = firstException
                    }
                } label: {
                    Text("处理")
                        .font(BsTypography.captionSmall.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, BsSpacing.md)
                        .padding(.vertical, BsSpacing.sm)
                        .background(BsColor.brandAzure, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Derived

    private var rangeDaysSorted: [AttendanceDay] {
        viewModel.rangeDays.values.sorted { $0.iso < $1.iso }
    }

    private var todayDay: AttendanceDay? {
        let cal = Calendar(identifier: .gregorian)
        return rangeDaysSorted.first(where: { cal.isDateInToday($0.date) })
            ?? rangeDaysSorted.last
    }

    private var visibleTimelineDays: [AttendanceDay] {
        switch viewModel.selectedRange {
        case .today:
            // Single row, but show a small back-history of the past week
            // for context (Apple Health daily summary feel).
            return rangeDaysSorted.suffix(7).reversed()
        case .week:
            return rangeDaysSorted.reversed()
        case .month, .year:
            // Calendar handles bulk display — only show exceptions in timeline.
            return rangeDaysSorted.filter { $0.isException }.reversed()
        }
    }

    private var timelineTitle: String {
        switch viewModel.selectedRange {
        case .today: return "近 7 日 timeline"
        case .week:  return "本周 timeline"
        case .month, .year:
            return "异常列表"
        }
    }

    private var exceptionCount: Int {
        rangeDaysSorted.filter { $0.isException }.count
    }

    // MARK: - Liquid progress derivation

    private var progressTitle: String {
        switch viewModel.selectedRange {
        case .today: return "今日工时"
        case .week:  return "本周工作日"
        case .month: return "本月工作日"
        case .year:  return "本年工作日"
        }
    }

    private var progressSubtitle: String {
        switch viewModel.selectedRange {
        case .today:
            let target = 8.0
            let h = todayDay?.workHours ?? 0
            return "\(Self.fmtHoursCompact(h)) / \(Int(target))h"
        case .week, .month, .year:
            let workDays = rangeDaysSorted.filter { $0.workState?.isWorkDay == true || $0.status == .normal || $0.status == .workingNow }
            let completed = workDays.filter { $0.workHours > 0 }.count
            let total = max(1, workDays.count)
            return "\(completed) / \(total) 工作日"
        }
    }

    private var progressValue: CGFloat {
        switch viewModel.selectedRange {
        case .today:
            let target = 8.0
            let h = todayDay?.workHours ?? 0
            return CGFloat(min(1.0, h / target))
        case .week, .month, .year:
            let workDays = rangeDaysSorted.filter { $0.workState?.isWorkDay == true || $0.status == .normal || $0.status == .workingNow }
            let completed = workDays.filter { $0.workHours > 0 }.count
            let total = max(1, workDays.count)
            return CGFloat(Double(completed) / Double(total))
        }
    }

    private var progressTone: Color {
        if progressValue >= 1.0 { return BsColor.brandMint }
        if progressValue > 0 { return BsColor.brandAzure }
        return BsColor.inkFaint
    }

    // MARK: - Format helpers

    private static func fmtHoursCompact(_ h: Double) -> String {
        guard h.isFinite, h >= 0 else { return "0h" }
        let whole = Int(h)
        let mins = Int(round((h - Double(whole)) * 60))
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }
}

// MARK: - LiquidProgressBar (横向流体进度条 — 流体设计语言保留位)
//
// 重用 LiquidFillShape，但水平展开 —— 把 shape 旋转 90° 让"水位"
// 从左→右流动。60Hz TimelineView 驱 phase。Reduce Motion 下 amp=0
// 退化为静态填充，仍保留色彩。

public struct LiquidProgressBar: View {
    let progress: CGFloat
    let tone: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: CGFloat, tone: Color) {
        self.progress = progress
        self.tone = tone
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track — Iter7 fix (用户反馈"考勤的进度条那个液体也太奇怪了
                // 黑色蓝色"): 旧版用 inkFaint 在 dark 视觉/某些设备上偏黑,
                // 跟 brandAzure 强对比像 bug。改成同色系超浅 tint —
                // 10% azure 让 track 仍然可见但完全跟流体填充协调。
                Capsule()
                    .fill(BsColor.brandAzure.opacity(0.10))

                // Liquid fill (rotated 90° so "progress" reads as horizontal)
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
                    let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate) * 1.4
                    let amp: CGFloat = reduceMotion ? 0 : 4
                    let width = max(0, min(1, progress)) * geo.size.width
                    LiquidFillShape(
                        progress: 1.0,
                        phase: phase,
                        tiltX: 0,
                        amplitude: amp,
                        frequency: 1.6
                    )
                    .fill(fillGradient)
                    .frame(width: width, height: geo.size.height)
                    .rotationEffect(.degrees(-90), anchor: .center)
                    .frame(width: width, height: geo.size.height)
                    .clipShape(Capsule())
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(BsColor.brandAzure.opacity(0.18), lineWidth: 0.5)
            )
        }
        .animation(.smooth(duration: 0.6), value: progress)
        .accessibilityElement()
        .accessibilityLabel("进度 \(Int(progress * 100)) percent")
    }

    // Iter7: flow palette gradient (azure → mint) — matches dashboard hero
    // card 的液体色彩。当 tone 是 danger/warning（异常态）则换 coral 渐变,
    // 让色彩本身承载状态信息（绿/蓝=正常,珊瑚红=异常）。
    private var fillGradient: LinearGradient {
        // tone 由 progressTone 传入: brandMint(完成) / brandAzure(进行中) /
        // inkFaint(未开始)。后两种统一走 azure→mint flow palette。
        // 完成态保持 mint 主导（青绿成功反馈）。
        let colors: [Color]
        if tone == BsColor.brandMint {
            colors = [BsColor.brandMint, BsColor.brandAzure]
        } else if tone == BsColor.inkFaint {
            // 未开始: 用极淡 azure→mint, fill 宽度本身=0 时也不会显示,
            // 但兜底美观。
            colors = [BsColor.brandAzure.opacity(0.6), BsColor.brandMint.opacity(0.6)]
        } else {
            colors = [BsColor.brandAzure, BsColor.brandMint]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - AttendanceDayDetailSheet
//
// 点击日历格子 / timeline 行 → 弹出 detail sheet 显示这一天的全部
// 信息：上下班时间 / 备注 / 异常 / 排班 / 请假等。

public struct AttendanceDayDetailSheet: View {
    let day: AttendanceDay

    public init(day: AttendanceDay) {
        self.day = day
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                header
                clockTimes
                if day.isException, let exc = day.exceptionLabel {
                    exceptionBlock(exc)
                }
                if let dws = day.workState {
                    scheduleBlock(dws)
                }
                if let notes = day.attendance?.notes, !notes.isEmpty {
                    notesBlock(notes)
                }
            }
            .padding(BsSpacing.lg)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDate)
                .font(BsTypography.largeTitle)
                .foregroundStyle(BsColor.ink)
            HStack(spacing: BsSpacing.sm) {
                BsTagPill(day.label, tone: pillTone, icon: pillIcon)
                if day.workHours > 0 {
                    Text(Self.fmtHoursCompact(day.workHours))
                        .font(BsTypography.bodyMedium)
                        .foregroundStyle(BsColor.inkMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    private var clockTimes: some View {
        BsContentCard {
            HStack(spacing: BsSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("上班")
                        .font(BsTypography.label)
                        .foregroundStyle(BsColor.inkMuted)
                        .textCase(.uppercase)
                    Text(day.clockIn.map { Self.fmtTime($0) } ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(BsColor.ink)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("下班")
                        .font(BsTypography.label)
                        .foregroundStyle(BsColor.inkMuted)
                        .textCase(.uppercase)
                    Text(day.clockOut.map { Self.fmtTime($0) } ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(BsColor.ink)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func exceptionBlock(_ msg: String) -> some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                BsSectionTitle("异常", accent: .coral)
                Text(msg)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.danger)
            }
        }
    }

    @ViewBuilder
    private func scheduleBlock(_ dws: DailyWorkState) -> some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                BsSectionTitle("排班", accent: .azure)
                if let s = dws.expectedStart, let e = dws.expectedEnd {
                    Text("应班 \(s.prefix(5)) - \(e.prefix(5))")
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.ink)
                }
                Text("状态：\(WorkStateLabels.label(state: dws.state, leaveType: dws.leaveType))")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
                if let src = WorkStateSource.label(dws.source) {
                    Text("来源：\(src)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }
        }
    }

    @ViewBuilder
    private func notesBlock(_ notes: String) -> some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                BsSectionTitle("备注", accent: .mint)
                Text(notes)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
            }
        }
    }

    private var pillTone: BsTagTone {
        switch day.status {
        case .normal, .fieldWork:    return .success
        case .workingNow:            return .brand
        case .onLeave:               return .warning
        case .businessTrip:          return .admin
        case .publicHoliday, .weekendRest: return .neutral
        case .absent, .late, .earlyLeave: return .danger
        case .future, .unknown:      return .neutral
        }
    }

    private var pillIcon: String? {
        switch day.status {
        case .normal:        return "checkmark.circle.fill"
        case .workingNow:    return "clock.fill"
        case .onLeave:       return "calendar.badge.minus"
        case .businessTrip:  return "airplane"
        case .fieldWork:     return "figure.walk"
        case .publicHoliday: return "sun.max.fill"
        case .weekendRest:   return "bed.double.fill"
        case .absent, .late, .earlyLeave: return "exclamationmark.triangle.fill"
        default:             return nil
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return f.string(from: day.date)
    }

    private static func fmtTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func fmtHoursCompact(_ h: Double) -> String {
        let whole = Int(h)
        let mins = Int(round((h - Double(whole)) * 60))
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }
}

#Preview {
    AttendanceView()
}
