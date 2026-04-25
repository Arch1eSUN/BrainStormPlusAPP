import Foundation
import Combine
import CoreLocation
import Supabase

public enum ClockState: String {
    case ready, clockedIn, done
}

public enum FenceState: String {
    case idle, acquiring, inFence, outOfFence, error
}

// ══════════════════════════════════════════════════════════════════
// AttendanceViewModel — v2 (Iter6 §A.1)
//
// Two big changes:
//   (1) Range-aware data scope (本日 / 本周 / 本月 / 本年).
//       Pulls `attendance` + `daily_work_state` for the selected range
//       and exposes a unified `[String: AttendanceDay]` map keyed by
//       ISO date string. Drives the new AttendanceView (KPI row +
//       calendar heat-map + timeline list).
//
//   (2) Optimistic clock-in/out (`optimisticPunch()`).
//       Old pattern (`await RPC → on success flip state + play anim`)
//       made the Liquid hero card sit "frozen" for the network
//       roundtrip — anim played late, button felt dead. The new path
//       flips clockState IMMEDIATELY (driving the liquid fill +
//       checkmark animations through @Published change), fires the
//       network call in the background, and on failure rolls back +
//       surfaces a polite banner.
// ══════════════════════════════════════════════════════════════════

@MainActor
public class AttendanceViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var clockState: ClockState = .ready
    @Published public var fenceState: FenceState = .idle
    @Published public var hasLocation: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var isInitializing: Bool = true
    @Published public var currentLocationName: String? = "Fetching Location..."
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    @Published public var today: Attendance? = nil
    /// Phase 4c：本周（周一→今天）打卡记录，供 Dashboard Weekly Cadence strip 消费。
    /// key = ISO date string "YYYY-MM-DD"；未打卡的日子 map 里没条目。
    @Published public var thisWeek: [String: Attendance] = [:]
    /// Brief flag that flips true right after a successful clock-in/out.
    /// Drives the success ripple animation in `AttendanceView`. Auto
    /// resets after ~1.2s.
    @Published public var justSucceeded: Bool = false

    // ── v2: Range data (Iter6 §A.1) ─────────────────────────────────
    /// Currently selected range scope on the Attendance page.
    @Published public var selectedRange: AttendanceRange = .today
    /// Merged per-day record (attendance + daily_work_state) keyed by
    /// ISO date string. Spans whatever range was last loaded —
    /// `loadRange(_:)` overwrites the map every time.
    @Published public var rangeDays: [String: AttendanceDay] = [:]
    /// First/last ISO date currently in `rangeDays` (drives calendar
    /// heat-map empty cells).
    @Published public var rangeFromISO: String = ""
    @Published public var rangeToISO: String = ""
    /// Range loading flag — separate from `isLoading` (the punch flag).
    @Published public var isRangeLoading: Bool = false

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override public init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        Task { await loadToday() }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            self.currentLocation = loc
            self.currentLocationName = "Location acquired (WGS84)"
            self.hasLocation = true
        }
    }

    public func loadToday() async {
        self.isInitializing = true
        defer { self.isInitializing = false }

        do {
            let session = try await supabase.auth.session
            let uid = session.user.id
            let today = Self.isoDateString(for: Date())

            let rows: [Attendance] = try await supabase
                .from("attendance")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .eq("date", value: today)
                .limit(1)
                .execute()
                .value
            let row = rows.first
            self.today = row
            if let row {
                if row.clockOut != nil {
                    self.clockState = .done
                } else if row.clockIn != nil {
                    self.clockState = .clockedIn
                } else {
                    self.clockState = .ready
                }
            } else {
                self.clockState = .ready
            }
        } catch {
            // 非阻塞失败：首次若无行或网络差，保持 ready
            self.clockState = .ready
        }
    }

    // MARK: - Optimistic punch (Iter6 §A.1 part 2)
    //
    // 用户在 dashboard 反馈：液体打卡卡按下按钮后要等 1-3 秒（网络）才有
    // 变化，期间 isLoading=true 但 clockState 不变 → 液体高度纹丝不动 →
    // "白瞎了我们的动画"。
    //
    // 新做法：
    //   1. 立刻 flip clockState（@Published change → 液面进度立即从 0 升起 /
    //      从 progress 切到 done 颜色 + checkmark icon），justSucceeded=true
    //      让 hero ripple 动画现在就跑。
    //   2. 后台发起 RPC，**不**阻塞 UI（isLoading=false 保持）。
    //   3. 失败 → 回滚 clockState 到 snapshot，errorMessage 弹"打卡未成功,
    //      请重试" + Haptic.error。
    //   4. 成功 → 静默（已经 flip 过了）+ loadToday() 校准 server 时间。

    /// 自动派发：根据当前状态 → optimistic clock-in 或 clock-out。
    /// 旧 `punch()` 名字保留作 alias，所有 call sites 不动。
    public func punch() async {
        await optimisticPunch()
    }

    public func optimisticPunch() async {
        guard clockState != .done else { return }
        guard let location = currentLocation else {
            self.fenceState = .error
            self.errorMessage = "定位未就绪,请先授权并等待定位"
            return
        }

        // ── 1. Snapshot rollback state ──────────────────────────────
        let previousState = clockState
        let previousToday = today
        let kind: ClockKind = (clockState == .ready) ? .in : .out

        // ── 2. Flip immediately (drives liquid + checkmark anim) ───
        let now = Date()
        var optimisticToday = today ?? Attendance(
            id: UUID(),
            userId: UUID(),  // placeholder; server returns real row via loadToday()
            date: Self.isoDateString(for: now),
            clockIn: nil,
            clockOut: nil,
            status: nil,
            notes: nil,
            workHours: nil,
            lateMinutes: nil,
            isFieldWork: nil,
            createdAt: now
        )
        switch kind {
        case .in:
            optimisticToday.clockIn = now
            self.clockState = .clockedIn
        case .out:
            optimisticToday.clockOut = now
            self.clockState = .done
        }
        self.today = optimisticToday
        self.errorMessage = nil
        self.successMessage = nil
        self.fenceState = .acquiring
        Haptic.success()
        self.justSucceeded = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { self?.justSucceeded = false }
        }

        // ── 3. RPC in background (don't await on the main path) ────
        do {
            let session = try await supabase.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL.appendingPathComponent("api/mobile/attendance/clock")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "type": kind.rawValue,
                "location": [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude
                ],
                "device_info": "iOS App"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let http = response as? HTTPURLResponse else {
                rollback(toState: previousState, today: previousToday, reason: "网络异常,请重试")
                return
            }

            if http.statusCode == 200, json?["data"] != nil {
                // ── 4a. Success → silently reconcile with server ────
                self.fenceState = .inFence
                self.successMessage = (kind == .in) ? "上班打卡成功!" : "下班打卡成功!"
                await loadToday() // 用真实 server clock_in/clock_out 覆盖 optimistic
            } else {
                // ── 4b. Server rejected → rollback ──────────────────
                let err = json?["error"] as? String ?? "打卡未成功,请重试"
                let isOutOfFence = err.range(of: "围栏|geofence", options: [.regularExpression, .caseInsensitive]) != nil
                self.fenceState = isOutOfFence ? .outOfFence : .error
                rollback(toState: previousState, today: previousToday, reason: err)
            }
        } catch {
            rollback(toState: previousState, today: previousToday, reason: "网络异常,请重试")
        }
    }

    /// 回滚 optimistic state（失败路径）。
    private func rollback(toState state: ClockState, today: Attendance?, reason: String) {
        self.clockState = state
        self.today = today
        self.justSucceeded = false
        self.errorMessage = reason
        Haptic.error()
    }

    // MARK: - Week cadence

    /// Phase 4c：拉本周（周一 → 今天）所有打卡记录，供 Dashboard Weekly Cadence strip 消费。
    /// Supabase `attendance` 表由 Web 端和 iOS 共享 —— 只读同一张表即可。
    public func loadThisWeek() async {
        do {
            let session = try await supabase.auth.session
            let uid = session.user.id

            let cal = Calendar(identifier: .gregorian)
            let today = Date()
            // 本周周一
            let weekday = cal.component(.weekday, from: today) // Sun=1 … Sat=7
            let daysFromMonday = (weekday + 5) % 7
            guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return }

            let fromStr = Self.isoDateString(for: monday)
            let toStr = Self.isoDateString(for: today)

            let rows: [Attendance] = try await supabase
                .from("attendance")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("date", value: fromStr)
                .lte("date", value: toStr)
                .execute()
                .value

            // 按 date string key 入 map，方便 Dashboard 用 iso 字符串索引
            var next: [String: Attendance] = [:]
            for row in rows { next[row.date] = row }
            self.thisWeek = next
        } catch {
            #if DEBUG
            print("[AttendanceVM] loadThisWeek failed:", error)
            #endif
        }
    }

    // MARK: - v2 Range loader (Iter6 §A.1 part 1)
    //
    // 拉一段日期范围内的 attendance + daily_work_state，merge 成
    // `[ISO: AttendanceDay]`。Attendance 提供实际打卡时间 / 工时 /
    // 异常分钟数；daily_work_state 提供"应班 / 请假 / 公休 / 出差 /
    // 外勤"等 state 标签。两边按日期 join，缺哪边就用 fallback 状态：
    //
    //   • 有 attendance → 用 clockIn/clockOut/lateMinutes derive status
    //   • 无 attendance + daily_work_state.state == public_holiday/weekend_rest
    //     → 公休
    //   • 无 attendance + daily_work_state.state == personal_leave 等
    //     → 请假 / 调休
    //   • 无 attendance + daily_work_state.state == business_trip / field_work
    //     → 出差 / 外勤
    //   • 无 attendance + 普通工作日已过 → 异常（缺卡）
    //   • 无 attendance + 未来 → 未到
    //
    // SQL 备注（如需要新 RPC `attendance_get_summary`）：
    //   SELECT a.*, d.state, d.expected_start, d.expected_end,
    //          d.is_work_day, d.flexible_hours, d.leave_type, d.is_paid
    //   FROM attendance a
    //   FULL OUTER JOIN daily_work_state d
    //     ON a.user_id = d.user_id AND a.date = d.work_date
    //   WHERE a.user_id = $1 AND a.date BETWEEN $2 AND $3
    //   ORDER BY a.date;

    public func setRange(_ range: AttendanceRange) {
        self.selectedRange = range
        Task { await loadRange(range) }
    }

    public func loadRange(_ range: AttendanceRange) async {
        let (start, end) = range.bounds(reference: Date())
        await loadRange(from: start, to: end)
    }

    public func loadRange(from start: Date, to end: Date) async {
        self.isRangeLoading = true
        defer { self.isRangeLoading = false }

        let fromStr = Self.isoDateString(for: start)
        let toStr = Self.isoDateString(for: end)
        self.rangeFromISO = fromStr
        self.rangeToISO = toStr

        do {
            let session = try await supabase.auth.session
            let uid = session.user.id

            // 并发拉两张表（Supabase Swift SDK 各自是 async let）
            async let attRows: [Attendance] = supabase
                .from("attendance")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("date", value: fromStr)
                .lte("date", value: toStr)
                .execute()
                .value

            async let dwsRows: [DailyWorkState] = supabase
                .from("daily_work_state")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("work_date", value: fromStr)
                .lte("work_date", value: toStr)
                .execute()
                .value

            let (attendances, dws): ([Attendance], [DailyWorkState]) = try await (attRows, dwsRows)

            // Merge by ISO date.
            var attMap: [String: Attendance] = [:]
            for r in attendances { attMap[r.date] = r }
            var dwsMap: [String: DailyWorkState] = [:]
            for r in dws { dwsMap[r.workDate] = r }

            var merged: [String: AttendanceDay] = [:]
            // Walk every day in range so calendar heat-map has empty cells.
            let cal = Calendar(identifier: .gregorian)
            var cursor = start
            let today = Date()
            while cursor <= end {
                let iso = Self.isoDateString(for: cursor)
                let isFuture = cal.compare(cursor, to: today, toGranularity: .day) == .orderedDescending
                merged[iso] = AttendanceDay.derive(
                    iso: iso,
                    date: cursor,
                    attendance: attMap[iso],
                    workState: dwsMap[iso],
                    isFuture: isFuture
                )
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }

            self.rangeDays = merged
        } catch {
            #if DEBUG
            print("[AttendanceVM] loadRange failed:", error)
            #endif
            // Don't clobber existing rangeDays on failure — keep last good.
        }
    }

    // MARK: - Helpers

    private enum ClockKind: String { case `in`, out }

    private static func isoDateString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current  // 用户本地（CNST 北京）
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - AttendanceRange

/// Top-of-page segmented scope. Each maps to a date interval.
public enum AttendanceRange: String, CaseIterable, Identifiable {
    case today, week, month, year

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: return "本日"
        case .week:  return "本周"
        case .month: return "本月"
        case .year:  return "本年"
        }
    }

    /// (start, end) inclusive. All dates are start-of-day.
    public func bounds(reference: Date) -> (start: Date, end: Date) {
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: reference)
        switch self {
        case .today:
            return (startOfToday, startOfToday)
        case .week:
            // Monday-anchored week (Asia 习惯)
            let weekday = cal.component(.weekday, from: reference) // Sun=1 … Sat=7
            let daysFromMonday = (weekday + 5) % 7
            let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) ?? startOfToday
            let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday
            return (monday, sunday)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: reference)
            let firstOfMonth = cal.date(from: comps) ?? startOfToday
            let range = cal.range(of: .day, in: .month, for: reference) ?? 1..<31
            let lastOfMonth = cal.date(byAdding: .day, value: range.count - 1, to: firstOfMonth) ?? firstOfMonth
            return (firstOfMonth, lastOfMonth)
        case .year:
            let comps = cal.dateComponents([.year], from: reference)
            let firstOfYear = cal.date(from: comps) ?? startOfToday
            var endComps = DateComponents()
            endComps.year = (comps.year ?? 0) + 1
            endComps.day = -1
            let lastOfYear = cal.date(byAdding: endComps, to: firstOfYear) ?? firstOfYear
            return (firstOfYear, lastOfYear)
        }
    }
}

// MARK: - AttendanceDay (merged record for one calendar day)

/// One row per day for the new Attendance page.
/// Composed from `attendance` (the punch row) + `daily_work_state`
/// (the schedule/leave/holiday row). Either side may be missing.
public struct AttendanceDay: Identifiable, Hashable {
    public enum Status: String, Hashable {
        case normal       // 正常出勤
        case workingNow   // 进行中（已上班未下班）
        case onLeave      // 请假
        case businessTrip // 出差
        case fieldWork    // 外勤
        case publicHoliday// 公休/法定假
        case weekendRest  // 周末休息
        case absent       // 缺卡 / 旷工
        case late         // 迟到
        case earlyLeave   // 早退
        case future       // 未到
        case unknown
    }

    public var id: String { iso }
    public let iso: String
    public let date: Date
    public let attendance: Attendance?
    public let workState: DailyWorkState?
    public let status: Status
    public let workHours: Double          // 0 if no clock-in
    public let isException: Bool          // 迟到/早退/缺卡
    public let exceptionLabel: String?    // "迟到 23 分钟" 等

    public var clockIn: Date? { attendance?.clockIn }
    public var clockOut: Date? { attendance?.clockOut }

    /// Short label for the status chip (driving CalendarView color + Timeline pill).
    public var label: String {
        switch status {
        case .normal:        return "正常"
        case .workingNow:    return "进行中"
        case .onLeave:
            if let lt = workState?.leaveType, let mapped = WorkStateLabels.leaveType[lt] {
                return mapped
            }
            return "请假"
        case .businessTrip:  return "出差"
        case .fieldWork:     return "外勤"
        case .publicHoliday: return workState?.state == "public_holiday" ? "法定假" : "公休"
        case .weekendRest:   return "休息"
        case .absent:        return "缺卡"
        case .late:          return "迟到"
        case .earlyLeave:    return "早退"
        case .future:        return "未到"
        case .unknown:       return "—"
        }
    }

    static func derive(
        iso: String,
        date: Date,
        attendance: Attendance?,
        workState: DailyWorkState?,
        isFuture: Bool
    ) -> AttendanceDay {
        // Compute work hours
        let hours: Double = {
            if let h = attendance?.workHours, h > 0 { return h }
            if let inD = attendance?.clockIn {
                if let outD = attendance?.clockOut {
                    return max(0, outD.timeIntervalSince(inD)) / 3600
                }
            }
            return 0
        }()

        // Detect exception
        let lateMin = attendance?.lateMinutes ?? 0
        let cal = Calendar(identifier: .gregorian)
        let isToday = cal.isDateInToday(date)

        // Decide status
        let status: Status
        var exceptionLabel: String? = nil
        var isException = false

        if isFuture {
            status = .future
        } else if let att = attendance {
            // We have a punch row. Late / Early / Working / Normal
            if att.clockOut == nil {
                if isToday {
                    status = .workingNow
                } else {
                    // Past day with clock-in but no clock-out → 早退/缺卡
                    status = .earlyLeave
                    exceptionLabel = "未打下班卡"
                    isException = true
                }
            } else if lateMin > 0 {
                status = .late
                exceptionLabel = "迟到 \(lateMin) 分钟"
                isException = true
            } else if att.isFieldWork == true {
                status = .fieldWork
            } else {
                status = .normal
            }
        } else if let dws = workState {
            switch dws.state {
            case "public_holiday":  status = .publicHoliday
            case "weekend_rest":    status = .weekendRest
            case "personal_leave",
                 "comp_time":       status = .onLeave
            case "business_trip":   status = .businessTrip
            case "field_work":      status = .fieldWork
            case "absent":
                status = .absent
                exceptionLabel = "缺卡"
                isException = true
            case "normal":
                if dws.isWorkDay == false {
                    status = .weekendRest
                } else if isFuture || isToday {
                    status = .future
                } else {
                    // Past expected workday with no attendance → absent
                    status = .absent
                    exceptionLabel = "缺卡"
                    isException = true
                }
            case "pending", "rest":
                status = .weekendRest
            default:
                status = .unknown
            }
        } else {
            // No attendance, no daily_work_state. Default by weekday.
            let weekday = cal.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)  // Sun / Sat
            if isWeekend {
                status = .weekendRest
            } else if isToday {
                status = .future  // 未到（今日工作日尚未打卡，但日仍在跑）
            } else {
                status = .absent
                exceptionLabel = "缺卡"
                isException = true
            }
        }

        return AttendanceDay(
            iso: iso,
            date: date,
            attendance: attendance,
            workState: workState,
            status: status,
            workHours: hours,
            isException: isException,
            exceptionLabel: exceptionLabel
        )
    }
}
