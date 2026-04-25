import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// AttendanceView —— 用户自己的考勤主页（重新设计 v1.5）
//
// v1.5 ("Apple Health daily summary" pivot, 2026-04-25)
//
// 5 轮迭代后用户仍然觉得 hero 下方信息太挤、有重复。本轮把 v1.4
// 的 "Timeline card + Status footer + 单独 Week strip 段" 三段
// 合并成 一张 "Today + Week" content card：
//
//   ┌── HERO（保留 Liquid-Fill）──────────────────────┐
//   │ statusPill · 8h 12m · subtitle · CTA           │
//   └────────────────────────────────────────────────┘
//
//   ┌── BsContentCard ────────────────────────────────┐
//   │ 上班 09:02  ─────[ 8h 12m pill ]─────  下班 18:14│
//   │                                                 │
//   │ ── 本周 ─────────────────────────────────────── │
//   │  ▇  ▆  ▅  ▄  ▃    ·  ·                          │
//   │  一 二 三 四 五   六 日                          │
//   └─────────────────────────────────────────────────┘
//
// 关键删减（vs v1.4）：
//   • 去掉 "今日时间线" 卡标题 + statusFooter —— hero 的 statusPill 已表达
//   • 去掉 timeline header 的 "8h 12m" digital readout —— hero heroNumber
//     已是同一个数字的 48pt 正文，二次显示纯属噪音
//   • 把 punch endpoints 收紧到一行 + 中央 duration pill,liquid-fill 进度
//     已经在 hero 表达，timeline 不再二次画 progressFraction
//   • 周条改成 Apple Fitness Activity 风格的 hours bar chart —— 直接消化
//     Attendance.workHours 数据，带"本周累计/工作日完成数"副标
//
// 嵌入模式（isEmbedded=true）：去掉 NavigationStack 包壳，由父级提供
// ══════════════════════════════════════════════════════════════════

public struct AttendanceView: View {
    @StateObject private var viewModel = AttendanceViewModel()

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
                // ─── 1. Signature Hero —— 液体打卡卡 ─────────────────
                AttendanceHeroCard(
                    viewModel: viewModel,
                    isEmbedded: true,
                    todayState: nil
                )

                // ─── 2. 今日 + 本周 合并卡 ──────────────────────────
                summaryCard
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
            await viewModel.loadThisWeek()
        }
        .task(id: "attendance-load") {
            await viewModel.loadToday()
            await viewModel.loadThisWeek()
        }
    }

    // MARK: - Combined summary card (Today punch strip + Week activity bars)

    private var summaryCard: some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                punchStripRow
                Divider()
                    .background(BsColor.borderSubtle)
                weekActivitySection
            }
        }
    }

    // MARK: - Today punch strip
    //
    // 一行：上班时间 ─── [duration pill] ─── 下班时间
    //   • 未打卡        → 空 endpoints + dashed line
    //   • clockedIn     → 左 endpoint Azure 实，右 endpoint 镂空（脉动）+ 实时累计 pill
    //   • done          → 双端 endpoints 实 Mint，pill 显示总工时

    @ViewBuilder
    private var punchStripRow: some View {
        HStack(alignment: .center, spacing: BsSpacing.sm) {
            punchEndpoint(label: "上班", time: viewModel.today?.clockIn, alignment: .leading)
            punchTrack
            punchEndpoint(label: "下班", time: viewModel.today?.clockOut, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func punchEndpoint(label: String, time: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
            Text(Self.fmtTime(time))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(time == nil ? BsColor.inkFaint : BsColor.ink)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 56, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// 中央 track：dashed/solid line + duration pill 浮于中央
    @ViewBuilder
    private var punchTrack: some View {
        ZStack {
            // line —— 未打卡 dashed，已打卡渐变
            GeometryReader { geo in
                let mid = geo.size.height / 2
                if viewModel.clockState == .ready {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: mid))
                        p.addLine(to: CGPoint(x: geo.size.width, y: mid))
                    }
                    .stroke(
                        BsColor.inkFaint.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5])
                    )
                } else {
                    LinearGradient(
                        colors: [BsColor.brandAzure.opacity(0.55), trackTone.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .position(x: geo.size.width / 2, y: mid)
                }
            }
            .frame(height: 24)

            // 中央 duration pill
            durationPill
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var durationPill: some View {
        HStack(spacing: 4) {
            Image(systemName: durationIcon)
                .font(.system(.caption2, weight: .semibold))
            Text(durationText)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(trackTone)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(BsColor.surfacePrimary)
                .shadow(color: trackTone.opacity(0.18), radius: 6, y: 1)
        )
        .overlay(
            Capsule().stroke(trackTone.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var durationIcon: String {
        switch viewModel.clockState {
        case .ready:     return "circle.dashed"
        case .clockedIn: return "hourglass"
        case .done:      return "checkmark"
        }
    }

    private var durationText: String {
        switch viewModel.clockState {
        case .ready:
            return "未开始"
        case .clockedIn:
            if let inDate = viewModel.today?.clockIn {
                return Self.fmtDuration(Date().timeIntervalSince(inDate))
            }
            return "进行中"
        case .done:
            if let h = viewModel.today?.workHours {
                return Self.fmtHoursCompact(h)
            }
            if let inDate = viewModel.today?.clockIn,
               let outDate = viewModel.today?.clockOut {
                return Self.fmtDuration(outDate.timeIntervalSince(inDate))
            }
            return "已完成"
        }
    }

    private var trackTone: Color {
        switch viewModel.clockState {
        case .ready:     return BsColor.inkFaint
        case .clockedIn: return BsColor.brandAzure
        case .done:      return BsColor.brandMint
        }
    }

    // MARK: - Week activity (Apple Fitness 风格 bar chart)

    @ViewBuilder
    private var weekActivitySection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("本周")
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                Spacer(minLength: 0)
                Text(weekSubtitle)
                    .font(BsTypography.captionSmall)
                    .monospacedDigit()
                    .foregroundStyle(BsColor.inkMuted)
            }

            WeekActivityBars(days: weekActivityDays)
                .frame(height: 84)
        }
    }

    /// "本周已完成 4/5 · 累计 32.5h" 副标
    private var weekSubtitle: String {
        let completed = weekActivityDays.prefix(5).filter { $0.workHours > 0 }.count
        let totalHours = weekActivityDays.reduce(0) { $0 + $1.workHours }
        let totalStr: String = {
            guard totalHours > 0 else { return "未累计" }
            let whole = Int(totalHours)
            let mins = Int(round((totalHours - Double(whole)) * 60))
            if mins == 0 { return "累计 \(whole)h" }
            return "累计 \(whole)h \(mins)m"
        }()
        return "\(completed)/5 个工作日 · \(totalStr)"
    }

    /// 7-day cadence bars from viewModel.thisWeek (Mon-Sun).
    /// 高度 = workHours / 8h，封顶 1.0；今日高亮，过去未打卡 = 空白 baseline。
    private var weekActivityDays: [WeekActivityDay] {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let labels = ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).map { idx in
            let dayDiff = idx - mondayOffset
            let isToday = (dayDiff == 0)
            let isFuture = dayDiff > 0
            let date = cal.date(byAdding: .day, value: dayDiff, to: today) ?? today
            let iso = Self.isoDate(date)
            let record = viewModel.thisWeek[iso]

            // 计算 workHours：优先取 server 的 workHours，否则按 clockIn/clockOut 补算；
            // 进行中（today + clockedIn）按当前 elapsed 估算，让今日 bar 实时跟随。
            let computedHours: Double = {
                if let h = record?.workHours, h > 0 { return h }
                if let inD = record?.clockIn {
                    if let outD = record?.clockOut {
                        return max(0, outD.timeIntervalSince(inD)) / 3600
                    }
                    if isToday {
                        return max(0, Date().timeIntervalSince(inD)) / 3600
                    }
                }
                return 0
            }()

            return WeekActivityDay(
                id: iso,
                shortLabel: labels[idx],
                workHours: computedHours,
                isToday: isToday,
                isInFuture: isFuture
            )
        }
    }

    // MARK: - Formatting helpers

    private static func fmtTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func fmtHoursCompact(_ h: Double) -> String {
        guard h.isFinite, h >= 0 else { return "—" }
        let clamped = min(h, 99.9)
        let whole = Int(clamped)
        let mins = Int(round((clamped - Double(whole)) * 60))
        if mins == 60 { return "\(whole + 1)h 0m" }
        return "\(whole)h \(mins)m"
    }

    private static func fmtDuration(_ seconds: TimeInterval) -> String {
        let safe = max(0, seconds)
        let h = Int(safe) / 3600
        let m = (Int(safe) % 3600) / 60
        return "\(h)h \(m)m"
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }
}

// MARK: - WeekActivityDay model
//
// 比 WeekDayCadence 多带 workHours 数据；保留为 fileprivate（非 design-system
// 候选 —— 仅 Attendance 自己消费，不需要进 Shared/DesignSystem）。

private struct WeekActivityDay: Identifiable, Hashable {
    let id: String
    let shortLabel: String
    let workHours: Double
    let isToday: Bool
    let isInFuture: Bool
}

// MARK: - WeekActivityBars
//
// Apple Fitness Activity-strip 灵感的 7 列竖 bar：
//   • 高度 = workHours / 8h（封顶 1.0），有最小可见高度（>0 时至少 8% 满）
//   • 颜色：今日 → Azure 实色 + 顶端 highlight；过去 → Mint；未来 → 空白圆角
//   • Reduce Motion 下进入动画自动跳过

private struct WeekActivityBars: View {
    let days: [WeekActivityDay]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared: Bool = false

    var body: some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width / CGFloat(max(1, days.count))
            let barWidth = min(columnWidth - 8, 18)
            let chartHeight = geo.size.height - 18  // 18pt 让出底部 weekday label
            let barAreaHeight = max(8, chartHeight)

            HStack(spacing: 0) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            // 背景 track（满高灰）
                            Capsule()
                                .fill(BsColor.inkFaint.opacity(0.10))
                                .frame(width: barWidth, height: barAreaHeight)

                            // 实际 bar
                            Capsule()
                                .fill(barFill(for: day))
                                .frame(
                                    width: barWidth,
                                    height: hasAppeared ? barHeight(for: day, total: barAreaHeight) : 0
                                )
                                .overlay(alignment: .top) {
                                    // 顶端 highlight hairline —— 给"已完成"的 bar
                                    // 一抹 Apple Fitness 同款光泽
                                    if barHeight(for: day, total: barAreaHeight) > 6 {
                                        Capsule()
                                            .fill(Color.white.opacity(0.45))
                                            .frame(width: barWidth, height: 2)
                                            .padding(.top, 1)
                                    }
                                }
                        }
                        .frame(height: barAreaHeight, alignment: .bottom)

                        Text(day.shortLabel)
                            .font(.custom("Inter-Medium", size: 11, relativeTo: .caption2))
                            .foregroundStyle(
                                day.isToday ? BsColor.brandAzure : BsColor.inkMuted
                            )
                    }
                    .frame(width: columnWidth)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(a11yLabel(for: day))
                }
            }
        }
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.06)) {
                    hasAppeared = true
                }
            }
        }
    }

    private func barHeight(for day: WeekActivityDay, total: CGFloat) -> CGFloat {
        guard !day.isInFuture, day.workHours > 0 else { return 0 }
        let fraction = min(1.0, day.workHours / 8.0)
        let minVisible: CGFloat = 6
        return max(minVisible, CGFloat(fraction) * total)
    }

    private func barFill(for day: WeekActivityDay) -> LinearGradient {
        if day.isInFuture {
            return LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
        }
        if day.isToday {
            return LinearGradient(
                colors: [BsColor.brandAzure, BsColor.brandAzure.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if day.workHours > 0 {
            return LinearGradient(
                colors: [BsColor.brandMint, BsColor.brandMint.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [BsColor.inkFaint.opacity(0.18), BsColor.inkFaint.opacity(0.18)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func a11yLabel(for day: WeekActivityDay) -> String {
        if day.isInFuture { return "周\(day.shortLabel)，未到" }
        if day.workHours <= 0 { return "周\(day.shortLabel)，未打卡" }
        let whole = Int(day.workHours)
        let mins = Int(round((day.workHours - Double(whole)) * 60))
        let prefix = day.isToday ? "今天，周\(day.shortLabel)" : "周\(day.shortLabel)"
        return "\(prefix)，工作 \(whole) 小时 \(mins) 分"
    }
}

#Preview {
    AttendanceView()
}
