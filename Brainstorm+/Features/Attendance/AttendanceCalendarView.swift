import SwiftUI

// ══════════════════════════════════════════════════════════════════
// AttendanceCalendarView — 月历 / 年历 heat-map
//
// Iter6 §A.1：状态色编码（Apple Health Activity Calendar 风）。
//   • 出勤      → brandAzure
//   • 请假      → warning (= brandCoral)
//   • 外勤      → brandMint
//   • 出差      → brandCoral
//   • 公休/休息  → inkFaint
//   • 异常      → danger
//   • 未到      → 极淡灰
//   • 进行中    → brandAzure + 内圈高光（"今天"指示）
//
// 行为：
//   • 点击格子 → expand 当日 timeline detail（onTap callback）
//   • 切换 range（month/year）时格子用 .animation(.smooth) 过渡颜色
//   • 周首列 = 周一（CN 习惯）
// ══════════════════════════════════════════════════════════════════

public struct AttendanceCalendarView: View {
    let range: AttendanceRange
    let days: [String: AttendanceDay]
    let rangeFromISO: String
    let rangeToISO: String
    let onSelectDay: (AttendanceDay) -> Void

    @State private var selectedISO: String? = nil

    public init(
        range: AttendanceRange,
        days: [String: AttendanceDay],
        rangeFromISO: String,
        rangeToISO: String,
        onSelectDay: @escaping (AttendanceDay) -> Void
    ) {
        self.range = range
        self.days = days
        self.rangeFromISO = rangeFromISO
        self.rangeToISO = rangeToISO
        self.onSelectDay = onSelectDay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            switch range {
            case .month:
                monthGrid
            case .year:
                yearGrid
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Month grid (single-month full calendar)

    @ViewBuilder
    private var monthGrid: some View {
        let cal = Calendar(identifier: .gregorian)
        let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let cells = monthCells(cal: cal)

        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            // Weekday header
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { lbl in
                    Text(lbl)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells, id: \.id) { cell in
                    cellView(cell)
                }
            }
        }
    }

    // MARK: - Year grid (12 month mini-grids)

    private var yearMonthFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f
    }

    private var yearMonthDates: [Date] {
        let cal = Calendar(identifier: .gregorian)
        guard let from = AttendanceCalendarView.isoToDate(rangeFromISO) else { return [] }
        return (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: from) }
    }

    @ViewBuilder
    private var yearGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: BsSpacing.md), count: 3), spacing: BsSpacing.md) {
            ForEach(Array(yearMonthDates.enumerated()), id: \.offset) { _, monthDate in
                miniMonth(date: monthDate, formatter: yearMonthFormatter, cal: Calendar(identifier: .gregorian))
            }
        }
    }

    @ViewBuilder
    private func miniMonth(date: Date, formatter: DateFormatter, cal: Calendar) -> some View {
        let cells = miniMonthCells(for: date, cal: cal)
        VStack(alignment: .leading, spacing: 4) {
            Text(formatter.string(from: date))
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 7), spacing: 1.5) {
                ForEach(cells, id: \.id) { cell in
                    miniCellView(cell)
                }
            }
        }
    }

    // MARK: - Cell views

    @ViewBuilder
    private func cellView(_ cell: CalendarCell) -> some View {
        if let iso = cell.iso, let day = days[iso] {
            Button {
                selectedISO = iso
                onSelectDay(day)
                Haptic.selection()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color(for: day.status).opacity(intensity(for: day)))
                    if cell.dayNumber > 0 {
                        Text("\(cell.dayNumber)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(textColor(for: day))
                            .monospacedDigit()
                    }
                    if day.status == .workingNow {
                        // Apple Activity 风的"今天"高亮 ring
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BsColor.brandAzure, lineWidth: 1.5)
                    }
                    if selectedISO == iso {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BsColor.ink, lineWidth: 1.5)
                    }
                }
                .frame(height: 44)
                .animation(.smooth(duration: 0.25), value: day.status)
            }
            .buttonStyle(.plain)
        } else {
            // Empty leading/trailing slots
            Color.clear.frame(height: 44)
        }
    }

    @ViewBuilder
    private func miniCellView(_ cell: CalendarCell) -> some View {
        if let iso = cell.iso, let day = days[iso] {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(for: day.status).opacity(intensity(for: day)))
                .frame(height: 10)
                .overlay {
                    if day.status == .workingNow {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(BsColor.brandAzure, lineWidth: 0.8)
                    }
                }
                .onTapGesture {
                    onSelectDay(day)
                    Haptic.selection()
                }
                .animation(.smooth(duration: 0.25), value: day.status)
        } else {
            Color.clear.frame(height: 10)
        }
    }

    // MARK: - Color rules

    private func color(for status: AttendanceDay.Status) -> Color {
        switch status {
        case .normal, .workingNow: return BsColor.brandAzure
        case .onLeave:             return BsColor.warning
        case .fieldWork:           return BsColor.brandMint
        case .businessTrip:        return BsColor.brandCoral
        case .publicHoliday,
             .weekendRest:         return BsColor.inkFaint
        case .absent, .late, .earlyLeave: return BsColor.danger
        case .future:              return BsColor.inkFaint
        case .unknown:             return BsColor.inkFaint
        }
    }

    private func intensity(for day: AttendanceDay) -> Double {
        switch day.status {
        case .future:                  return 0.10
        case .weekendRest, .publicHoliday: return 0.20
        case .normal where day.workHours >= 8: return 0.85
        case .normal:                  return 0.55
        case .workingNow:              return 0.55
        case .late, .earlyLeave, .absent: return 0.75
        case .onLeave, .fieldWork, .businessTrip: return 0.55
        case .unknown:                 return 0.10
        }
    }

    private func textColor(for day: AttendanceDay) -> Color {
        switch day.status {
        case .future, .weekendRest, .publicHoliday, .unknown:
            return BsColor.inkMuted
        default:
            return Color.white
        }
    }

    // MARK: - Cell calculation

    private struct CalendarCell: Hashable {
        let id: String
        let iso: String?
        let dayNumber: Int
    }

    private func monthCells(cal: Calendar) -> [CalendarCell] {
        guard let firstDate = AttendanceCalendarView.isoToDate(rangeFromISO),
              let lastDate = AttendanceCalendarView.isoToDate(rangeToISO) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstDate)
        let leadingPadding = (firstWeekday + 5) % 7  // Mon-anchored
        let totalDays = cal.dateComponents([.day], from: firstDate, to: lastDate).day! + 1

        var cells: [CalendarCell] = []
        for i in 0..<leadingPadding {
            cells.append(CalendarCell(id: "lead-\(i)", iso: nil, dayNumber: 0))
        }
        for d in 0..<totalDays {
            let date = cal.date(byAdding: .day, value: d, to: firstDate)!
            let iso = Self.isoFmt.string(from: date)
            let dayNum = cal.component(.day, from: date)
            cells.append(CalendarCell(id: iso, iso: iso, dayNumber: dayNum))
        }
        return cells
    }

    private func miniMonthCells(for monthDate: Date, cal: Calendar) -> [CalendarCell] {
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        let firstOfMonth = cal.date(from: comps) ?? monthDate
        let monthRange = cal.range(of: .day, in: .month, for: monthDate) ?? 1..<31
        let totalDays = monthRange.count
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadingPadding = (firstWeekday + 5) % 7

        var cells: [CalendarCell] = []
        for i in 0..<leadingPadding {
            cells.append(CalendarCell(id: "lead-\(monthDate.timeIntervalSince1970)-\(i)", iso: nil, dayNumber: 0))
        }
        for d in 0..<totalDays {
            let date = cal.date(byAdding: .day, value: d, to: firstOfMonth)!
            let iso = Self.isoFmt.string(from: date)
            cells.append(CalendarCell(id: iso, iso: iso, dayNumber: d + 1))
        }
        return cells
    }

    // MARK: - ISO helpers

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoToDate(_ iso: String) -> Date? {
        isoFmt.date(from: iso)
    }
}

// MARK: - Color legend (re-used by parent view)

public struct AttendanceCalendarLegend: View {
    public init() {}

    public var body: some View {
        HStack(spacing: BsSpacing.md) {
            legendDot(BsColor.brandAzure, "出勤")
            legendDot(BsColor.warning, "请假")
            legendDot(BsColor.brandMint, "外勤")
            legendDot(BsColor.brandCoral, "出差")
            legendDot(BsColor.danger, "异常")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
        }
    }
}
