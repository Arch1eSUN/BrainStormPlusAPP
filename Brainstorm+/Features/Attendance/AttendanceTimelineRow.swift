import SwiftUI

// ══════════════════════════════════════════════════════════════════
// AttendanceTimelineRow — 单日 timeline 列表行
//
// Iter6 §A.1：本日 / 本周 视图下的 timeline 列表，每天一行：
//   ┌────────────────────────────────────────────────┐
//   │ 周一 04-21    [正常 chip]   09:02 → 18:14      │
//   │ 8h 12m                                         │
//   └────────────────────────────────────────────────┘
//
// 异常情况下显示 pill（"迟到 23 分钟" 等），长按弹上下文菜单
// （查看详情 / 申请补卡 / 申请异常修正）。
// ══════════════════════════════════════════════════════════════════

public struct AttendanceTimelineRow: View {
    let day: AttendanceDay
    let onDetail: (AttendanceDay) -> Void
    let onRequestFix: (AttendanceDay) -> Void

    public init(
        day: AttendanceDay,
        onDetail: @escaping (AttendanceDay) -> Void,
        onRequestFix: @escaping (AttendanceDay) -> Void
    ) {
        self.day = day
        self.onDetail = onDetail
        self.onRequestFix = onRequestFix
    }

    public var body: some View {
        HStack(alignment: .center, spacing: BsSpacing.md) {
            // ── Date column ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayLabel)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
                Text(monthDay)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
            }
            .frame(width: 56, alignment: .leading)

            // ── Status chip + clock times ───────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: BsSpacing.sm) {
                    BsTagPill(day.label, tone: tone, icon: icon)
                    if let exc = day.exceptionLabel {
                        Text(exc)
                            .font(BsTypography.captionSmall.weight(.semibold))
                            .foregroundStyle(BsColor.danger)
                    }
                }

                if day.clockIn != nil || day.clockOut != nil {
                    HStack(spacing: 4) {
                        Text(clockTimeText)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(BsColor.inkMuted)
                            .monospacedDigit()
                        if day.workHours > 0 {
                            Text("· \(Self.fmtHoursCompact(day.workHours))")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(BsColor.inkMuted)
                                .monospacedDigit()
                        }
                    }
                } else if day.status == .future {
                    Text("尚未到")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }

            Spacer(minLength: 0)

            // ── Disclosure indicator ────────────────────────────────
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BsColor.inkFaint)
        }
        .padding(.vertical, BsSpacing.sm + 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onDetail(day)
            Haptic.light()
        }
        .contextMenu {
            Button {
                onDetail(day)
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }
            if day.isException || day.clockIn == nil {
                Button {
                    onRequestFix(day)
                } label: {
                    Label("申请补卡", systemImage: "doc.badge.plus")
                }
            }
            if day.isException {
                Button {
                    onRequestFix(day)
                } label: {
                    Label("申请异常修正", systemImage: "exclamationmark.bubble")
                }
            }
        }
    }

    // MARK: - Derived

    private var weekdayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: day.date).replacingOccurrences(of: "星期", with: "周")
    }

    private var monthDay: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: day.date)
    }

    private var clockTimeText: String {
        let inT = day.clockIn.map { Self.fmtTime($0) } ?? "—"
        let outT = day.clockOut.map { Self.fmtTime($0) } ?? "—"
        return "\(inT) → \(outT)"
    }

    private var tone: BsTagTone {
        switch day.status {
        case .normal, .fieldWork:    return .success
        case .workingNow:            return .brand
        case .onLeave:               return .warning
        case .businessTrip:          return .admin
        case .publicHoliday, .weekendRest: return .neutral
        case .absent, .late, .earlyLeave: return .danger
        case .future:                return .neutral
        case .unknown:               return .neutral
        }
    }

    private var icon: String? {
        switch day.status {
        case .normal:        return "checkmark.circle.fill"
        case .workingNow:    return "clock.fill"
        case .onLeave:       return "calendar.badge.minus"
        case .businessTrip:  return "airplane"
        case .fieldWork:     return "figure.walk"
        case .publicHoliday: return "sun.max.fill"
        case .weekendRest:   return "bed.double.fill"
        case .absent, .late, .earlyLeave: return "exclamationmark.triangle.fill"
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
        let whole = Int(h)
        let mins = Int(round((h - Double(whole)) * 60))
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }
}
