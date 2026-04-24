import Foundation
import Supabase

/// Mirrors Web `useScheduleData` in
/// `BrainStorm+-Web/src/app/dashboard/schedules/_hooks/use-schedule-data.ts`.
///
/// Batch C.3 — switched from single-date fetch to a 14-day range query with
/// an in-VM cache, matching Web's React Query `staleTime: 60s` semantics:
///
///   • `states` is a `[YYYY-MM-DD: DailyWorkState]` map populated by
///     `loadRange(from:to:)`. The current schedule view (timeline strip +
///     "今日状态" card) always renders from this cache, never from a live
///     re-fetch per date tap.
///   • `today` and `selectedDayState` are computed off `states`.
///   • `refresh()` invalidates the cache (sets `rangeFrom/rangeTo` to nil)
///     and re-fetches the current range. Pull-to-refresh on the view calls
///     this; ordinary date-strip taps just change `selectedDate`.
///   • The `staleAfter` TTL (60s) mirrors Web's React Query config — we use
///     it as an internal hint, not a hard cache eviction, since the VM
///     itself is recreated per view appearance.
///
/// The Web hook also fetches `profiles` + filters by scope. The iOS
/// Schedule surface is single-user ("my" view + today card), so we skip
/// the profile join and rely on RLS to restrict the query to `auth.uid()`.
@MainActor
@Observable
public final class ScheduleViewModel {
    // MARK: - Public state

    /// Selected date (iOS device-local, CNST).
    public var selectedDate = Date()

    /// Current view mode — mirrors Web's 4 modes from
    /// `_components/view-switcher.tsx`.
    public var viewMode: ScheduleViewMode = .my

    /// Range currently loaded in `states`. `nil` until first successful load.
    public private(set) var rangeFrom: String? = nil
    public private(set) var rangeTo: String? = nil

    /// In-VM cache: date-string → daily_work_state row. Key matches
    /// `DailyWorkState.workDate` ("YYYY-MM-DD"). Missing keys mean "no row
    /// on that date" (not yet fetched / not in DB).
    public private(set) var states: [String: DailyWorkState] = [:]

    public var isLoading = false
    public var errorMessage: String?

    /// Last successful load timestamp — lets callers decide when to refetch.
    /// Compared against `staleAfter` to mirror Web's `staleTime: 60s`.
    public private(set) var lastLoadedAt: Date? = nil

    /// Mirrors Web React Query `staleTime`. Not enforced internally —
    /// exposed so callers can do `if viewModel.isStale { await … }`.
    public static let staleAfter: TimeInterval = 60

    // MARK: - Derived

    /// State for the currently selected date (driven from the cache).
    public var selectedDayState: DailyWorkState? {
        states[Self.isoDateString(for: selectedDate)]
    }

    /// Legacy accessor — kept for `DayStateCardView(dws: viewModel.today)`
    /// call sites that weren't updated.
    public var today: DailyWorkState? { selectedDayState }

    /// Ordered 14-day strip starting at today (matches Web `my-view.tsx`
    /// `days` loop: `for i in 0..<14 { push(today + i) }`).
    public var upcoming14Days: [(date: Date, iso: String)] {
        Self.dateStrip(startingAt: Date(), count: 14)
    }

    /// Whether the current cache has exceeded `staleAfter`.
    public var isStale: Bool {
        guard let t = lastLoadedAt else { return true }
        return Date().timeIntervalSince(t) > Self.staleAfter
    }

    // MARK: - Loading

    /// Backwards-compatible single-date loader. Delegates to the 14-day
    /// "my" range so the current card view keeps working without touching
    /// its callers (MainTab, Dashboard, etc.).
    public func loadSchedules() async {
        await loadMyRange()
    }

    /// Load the current user's next 14 days into the in-VM cache.
    /// Used by the "my" view and by the default today card.
    public func loadMyRange() async {
        let today = Date()
        let end = Calendar.current.date(byAdding: .day, value: 13, to: today) ?? today
        await loadRange(from: today, to: end)
    }

    /// Fetch `daily_work_state` rows for a date range and replace the cache.
    /// The cache is replaced (not merged) so stale rows outside the new
    /// range don't linger — matches Web's per-query cache semantics.
    public func loadRange(from start: Date, to end: Date) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fromStr = Self.isoDateString(for: start)
        let toStr = Self.isoDateString(for: end)

        do {
            let session = try await supabase.auth.session
            let uid = session.user.id

            #if DEBUG
            print("[ScheduleVM] ▶ Fetching daily_work_state")
            print("[ScheduleVM]   uid = \(uid.uuidString)")
            print("[ScheduleVM]   from = \(fromStr)  to = \(toStr)")
            #endif

            // Web (use-schedule-data.ts:149-156):
            //   .from('daily_work_state')
            //   .select(...)
            //   .in('user_id', [...])
            //   .gte('work_date', from)
            //   .lte('work_date', to)
            let rows: [DailyWorkState] = try await supabase
                .from("daily_work_state")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("work_date", value: fromStr)
                .lte("work_date", value: toStr)
                .execute()
                .value

            #if DEBUG
            print("[ScheduleVM] ✓ Received \(rows.count) rows")
            #endif

            var next: [String: DailyWorkState] = [:]
            for row in rows {
                next[row.workDate] = row
            }

            self.states = next
            self.rangeFrom = fromStr
            self.rangeTo = toStr
            self.lastLoadedAt = Date()
        } catch {
            // 诊断：打印完整 error 到控制台，包含 type + underlying description
            #if DEBUG
            print("[ScheduleVM] loadRange failed — type: \(type(of: error)), detail:", error)
            if let ns = error as NSError? {
                print("  NSError domain: \(ns.domain), code: \(ns.code), userInfo: \(ns.userInfo)")
            }
            #endif
            let mapped = ErrorLocalizer.localize(error)
            // 附带简短技术提示让用户上报更精确
            self.errorMessage = "加载失败：\(mapped)"
        }
    }

    /// Invalidate the cache and re-fetch the current range. Wired to
    /// pull-to-refresh on the Schedule view.
    public func refresh() async {
        // Drop the cache so even a same-range re-load counts as fresh data.
        self.lastLoadedAt = nil
        // Re-fetch the same bounds if we have them, otherwise fall back to
        // the 14-day strip.
        if let f = rangeFrom, let t = rangeTo,
           let fd = Self.dateFrom(iso: f), let td = Self.dateFrom(iso: t) {
            await loadRange(from: fd, to: td)
        } else {
            await loadMyRange()
        }
    }

    // MARK: - Helpers

    static func isoDateString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func dateFrom(iso: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }

    static func dateStrip(startingAt start: Date, count: Int) -> [(date: Date, iso: String)] {
        var out: [(Date, String)] = []
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: start)
        for i in 0..<count {
            if let d = cal.date(byAdding: .day, value: i, to: anchor) {
                out.append((d, isoDateString(for: d)))
            }
        }
        return out
    }
}

/// Schedule view modes — mirrors Web
/// `_components/view-switcher.tsx`:
///   calendar | timeline | list | my
public enum ScheduleViewMode: String, CaseIterable, Identifiable, Hashable {
    case my
    case list
    case timeline
    case calendar

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .my:       return "我的"
        case .list:     return "列表"
        case .timeline: return "时间线"
        case .calendar: return "月视图"
        }
    }

    public var systemImage: String {
        switch self {
        case .my:       return "person.fill"
        case .list:     return "list.bullet"
        case .timeline: return "clock.fill"
        case .calendar: return "calendar"
        }
    }
}
