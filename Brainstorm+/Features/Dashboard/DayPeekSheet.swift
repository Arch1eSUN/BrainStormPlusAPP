import SwiftUI

// ══════════════════════════════════════════════════════════════════
// DayPeekSheet —— Phase 4c 周历 strip 长按摘要
//
// 触发：Dashboard `BsWeeklyCadenceStrip` 长按某一天（0.4s + Haptic.light）
// 呈现：`.sheet(presentationDetents:[.height(280)])`（不用 popover —
//       popover 在 iPhone 上行为不一致，系统有时强转 full-modal）。
//
// 数据源：
//   • `AttendanceViewModel.thisWeek`（Supabase `attendance` 表，
//     周一→今天的 [iso: Attendance] map，Dashboard 已在 task/refreshable
//     里 loadThisWeek()，本 sheet 只读 map 不再发请求）。
//   • `DashboardViewModel.todayState`（`daily_work_state`）仅当 day==today
//     时可用，用于补"假期/休息日"状态；其他日期 Dashboard 当前并不缓存
//     daily_work_state，所以 sheet 只根据 attendance 行存在与否 + late_minutes
//     给状态，不跨天查 daily_work_state（保持"不新建订阅 / 不动其他 VM"约束）。
//
// 渲染规则：
//   • 该日无 attendance 行：
//       - isInFuture → "这一天还没到"
//       - 否则        → "这一天没有打卡数据"
//   • 有行但只有 clockIn（today 正在进行）     → 状态=进行中，总工时显 —
//   • 有行 clockIn + clockOut：
//       - late_minutes > 0                    → 迟到
//       - 否则                                → 正常
//   • 总工时：优先 work_hours 字段；没有就 clockOut-clockIn 自算。
//
// 关闭：用户手动下拉 / 背景点击，系统默认关闭，不加 haptic（共同约束）。
// ══════════════════════════════════════════════════════════════════

// MARK: - Data model

/// 长按日摘要需要的全部字段 —— 给 sheet 渲染用。
/// `date` 是原始 Date（渲染周几 / 年月日），`iso` 是 YYYY-MM-DD。
struct DayPeekData {
    let date: Date
    let iso: String
    /// 原 attendance 行（可能 nil：该日未打卡）
    let attendance: Attendance?
    /// 是否未来日
    let isInFuture: Bool
}

// MARK: - Status classification

private enum DayPeekStatus {
    case noData             // 无 attendance 行
    case future             // 未来日
    case inProgress         // clockIn 但无 clockOut（通常是今天进行中）
    case normal             // clockIn + clockOut，无迟到
    case late(minutes: Int) // 迟到

    var label: String {
        switch self {
        case .noData:      return "无打卡"
        case .future:      return "未到"
        case .inProgress:  return "进行中"
        case .normal:      return "正常"
        case .late(let m): return "迟到 \(m) 分钟"
        }
    }

    var tint: Color {
        switch self {
        case .noData:     return BsColor.inkFaint
        case .future:     return BsColor.inkFaint
        case .inProgress: return BsColor.brandAzure
        case .normal:     return BsColor.brandMint
        case .late:       return BsColor.brandCoral
        }
    }

    static func classify(_ d: DayPeekData) -> DayPeekStatus {
        if d.attendance == nil {
            return d.isInFuture ? .future : .noData
        }
        guard let row = d.attendance else { return .noData }
        if row.clockIn != nil && row.clockOut == nil {
            return .inProgress
        }
        if row.clockIn != nil && row.clockOut != nil {
            if let late = row.lateMinutes, late > 0 {
                return .late(minutes: late)
            }
            return .normal
        }
        return .noData
    }
}

// MARK: - Sheet view

struct DayPeekSheet: View {
    let data: DayPeekData

    private static let weekdayNames = [
        "周日", "周一", "周二", "周三", "周四", "周五", "周六",
    ]

    var body: some View {
        let status = DayPeekStatus.classify(data)
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            header
            Divider()
                .opacity(0.5)
            bodyContent(status: status)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BsSpacing.xl)
        .padding(.top, BsSpacing.xl)
        .padding(.bottom, BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.pageBackground.ignoresSafeArea())
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(data.iso)
                .font(BsTypography.sectionTitle)
                .foregroundStyle(BsColor.ink)
            Text(weekdayLabel)
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    private var weekdayLabel: String {
        let idx = Calendar(identifier: .gregorian).component(.weekday, from: data.date) - 1
        return Self.weekdayNames[max(0, min(6, idx))]
    }

    // MARK: - Body

    @ViewBuilder
    private func bodyContent(status: DayPeekStatus) -> some View {
        switch status {
        case .noData:
            emptyRow(icon: "clock.badge.questionmark", text: "这一天没有打卡数据")
        case .future:
            emptyRow(icon: "calendar", text: "这一天还没到")
        case .inProgress, .normal, .late:
            summaryRows(status: status)
        }
    }

    @ViewBuilder
    private func summaryRows(status: DayPeekStatus) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            // Row: 打卡时间
            HStack(spacing: BsSpacing.xl) {
                timeColumn(title: "上班", date: data.attendance?.clockIn)
                timeColumn(title: "下班", date: data.attendance?.clockOut)
                Spacer(minLength: 0)
            }
            // Row: 工时 + 状态
            HStack(spacing: BsSpacing.xl) {
                metricColumn(title: "总工时", value: durationLabel)
                statusColumn(status: status)
                Spacer(minLength: 0)
            }
        }
    }

    private func timeColumn(title: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
            Text(formatTime(date))
                .font(BsTypography.statSmall)
                .foregroundStyle(BsColor.ink)
                .monospacedDigit()
        }
        .frame(minWidth: 88, alignment: .leading)
    }

    private func metricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
            Text(value)
                .font(BsTypography.statSmall)
                .foregroundStyle(BsColor.ink)
                .monospacedDigit()
        }
        .frame(minWidth: 88, alignment: .leading)
    }

    private func statusColumn(status: DayPeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("状态")
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
            HStack(spacing: 6) {
                Circle()
                    .fill(status.tint)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
            }
        }
    }

    private func emptyRow(icon: String, text: String) -> some View {
        HStack(spacing: BsSpacing.md) {
            Image(systemName: icon)
                .font(.system(.title3, weight: .light))
                .foregroundStyle(BsColor.inkFaint)
            Text(text)
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, BsSpacing.sm)
    }

    // MARK: - Formatting

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// 总工时 HH:MM —— 优先 `work_hours` 小时数；没有就 clockOut-clockIn。
    /// 进行中（无 clockOut）显 —。
    private var durationLabel: String {
        guard let row = data.attendance else { return "—" }
        // 进行中 → —
        guard row.clockOut != nil else { return "—" }
        // 优先 DB 汇总
        if let h = row.workHours, h > 0 {
            let total = Int((h * 60).rounded())
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        if let inD = row.clockIn, let outD = row.clockOut {
            let secs = max(0, Int(outD.timeIntervalSince(inD)))
            let hh = secs / 3600
            let mm = (secs % 3600) / 60
            return String(format: "%02d:%02d", hh, mm)
        }
        return "—"
    }
}
