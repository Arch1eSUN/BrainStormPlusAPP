import SwiftUI

// ══════════════════════════════════════════════════════════════════
// AttendanceKPIRow — 顶部 KPI 数字行（随 segmented range 切换内容）
//
// Iter6 §A.1 要求：本日 / 本周 / 本月 / 本年 各自有专属 KPI 集合。
//   • 本日：工时 · 状态 · 上下班时间
//   • 本周：出勤天 · 异常天 · 总工时 · 平均工时
//   • 本月：出勤天 · 异常天 · 请假天 · 外勤天 · 出差天 · 公休天 · 总工时
//   • 本年：同月，但累计
//
// 视觉规格：
//   • 主指标用 BsTypography.heroNumber (Outfit 48pt) 大字
//   • 副 KPI 用 BsStatTile / 小数字行
//   • 切换 range 时数字 .contentTransition(.numericText())
//   • 数字下方紧跟流体进度条（见 LiquidProgressBar）
// ══════════════════════════════════════════════════════════════════

public struct AttendanceKPIRow: View {
    let range: AttendanceRange
    let days: [AttendanceDay]   // already filtered to current range
    let today: AttendanceDay?

    public init(range: AttendanceRange, days: [AttendanceDay], today: AttendanceDay?) {
        self.range = range
        self.days = days
        self.today = today
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            switch range {
            case .today: todayContent
            case .week:  weekContent
            case .month: rangeContent(unit: "本月")
            case .year:  rangeContent(unit: "本年")
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayContent: some View {
        let hours = today?.workHours ?? 0
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)

        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(h)")
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("小时")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
                Text("\(m)")
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("分")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
            }

            HStack(spacing: BsSpacing.sm) {
                if let today {
                    BsTagPill(today.label, tone: tone(for: today.status), icon: icon(for: today.status))
                }
                if let inDate = today?.clockIn {
                    Text("上班 \(Self.fmtTime(inDate))")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if let outDate = today?.clockOut {
                    Text("· 下班 \(Self.fmtTime(outDate))")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
    }

    // MARK: - Week

    @ViewBuilder
    private var weekContent: some View {
        let attendDays = days.filter { $0.workHours > 0 || $0.status == .normal }.count
        let exceptionDays = days.filter { $0.isException }.count
        let totalHours = days.reduce(0.0) { $0 + $1.workHours }
        let avgHours = attendDays > 0 ? totalHours / Double(attendDays) : 0

        VStack(alignment: .leading, spacing: BsSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.fmtHoursCompact(totalHours))
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("总工时")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
            }

            HStack(spacing: BsSpacing.sm) {
                BsStatTile(value: "\(attendDays)", label: "出勤天", tone: .azure)
                BsStatTile(value: "\(exceptionDays)", label: "异常天", tone: exceptionDays > 0 ? .coral : .neutral)
                BsStatTile(value: Self.fmtHoursCompact(avgHours), label: "平均工时", tone: .mint)
            }
        }
    }

    // MARK: - Month / Year

    @ViewBuilder
    private func rangeContent(unit: String) -> some View {
        let attend = days.filter { $0.status == .normal || $0.workHours > 0 }.count
        let exception = days.filter { $0.isException }.count
        let leave = days.filter { $0.status == .onLeave }.count
        let field = days.filter { $0.status == .fieldWork }.count
        let trip = days.filter { $0.status == .businessTrip }.count
        let holiday = days.filter { $0.status == .publicHoliday || $0.status == .weekendRest }.count
        let totalHours = days.reduce(0.0) { $0 + $1.workHours }

        VStack(alignment: .leading, spacing: BsSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.fmtHoursCompact(totalHours))
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(unit)总工时")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
            }

            // 7 个 stat tile 在窄屏会挤 —— wrap 成两行
            VStack(spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    BsStatTile(value: "\(attend)", label: "出勤", tone: .azure)
                    BsStatTile(value: "\(exception)", label: "异常", tone: exception > 0 ? .coral : .neutral)
                    BsStatTile(value: "\(leave)", label: "请假", tone: .warning)
                    BsStatTile(value: "\(field)", label: "外勤", tone: .mint)
                }
                HStack(spacing: BsSpacing.sm) {
                    BsStatTile(value: "\(trip)", label: "出差", tone: .coral)
                    BsStatTile(value: "\(holiday)", label: "公休", tone: .neutral)
                    // Filler tiles for symmetry
                    Color.clear.frame(maxWidth: .infinity)
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tone(for status: AttendanceDay.Status) -> BsTagTone {
        switch status {
        case .normal:        return .success
        case .workingNow:    return .brand
        case .onLeave:       return .warning
        case .businessTrip:  return .admin
        case .fieldWork:     return .success
        case .publicHoliday: return .neutral
        case .weekendRest:   return .neutral
        case .absent, .late, .earlyLeave: return .danger
        case .future:        return .neutral
        case .unknown:       return .neutral
        }
    }

    private func icon(for status: AttendanceDay.Status) -> String? {
        switch status {
        case .normal:        return "checkmark.circle.fill"
        case .workingNow:    return "clock.fill"
        case .onLeave:       return "calendar.badge.minus"
        case .businessTrip:  return "airplane"
        case .fieldWork:     return "figure.walk"
        case .publicHoliday: return "sun.max.fill"
        case .weekendRest:   return "bed.double.fill"
        case .absent:        return "exclamationmark.triangle.fill"
        case .late:          return "exclamationmark.triangle.fill"
        case .earlyLeave:    return "exclamationmark.triangle.fill"
        case .future:        return "circle.dashed"
        case .unknown:       return nil
        }
    }

    private static func fmtTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func fmtHoursCompact(_ h: Double) -> String {
        guard h.isFinite, h >= 0 else { return "0h" }
        let whole = Int(h)
        let mins = Int(round((h - Double(whole)) * 60))
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }
}
