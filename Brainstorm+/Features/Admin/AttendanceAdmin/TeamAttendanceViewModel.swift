import Foundation
import Combine
import Supabase

/// Admin-tier 全员考勤 ViewModel。
/// 拉取所有 profiles + 指定日期的 attendance 记录，按 user_id 合并。
///
/// 权限：通过 `attendance` 表 RLS + admin/superadmin/manager 策略读所有行。
/// profiles 表也是 admin 可读所有。
@MainActor
public class TeamAttendanceViewModel: ObservableObject {

    // MARK: - Rendered row

    public struct Row: Identifiable, Hashable {
        public let id: UUID               // = profile.id
        public let profile: Profile
        public let attendance: Attendance?   // nil = 未打卡

        /// 共享 HH:mm formatter（避免每次 getter 都 alloc）
        fileprivate static let hhmmFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()

        public var fullName: String { profile.fullName ?? "未命名" }
        public var department: String { profile.department ?? "" }

        /// 显示状态：已打卡/已下班/请假/出差/外勤/未打卡
        public var statusLabel: String {
            guard let att = attendance else { return "未打卡" }
            if att.isFieldWork == true { return "外勤" }
            switch att.status?.lowercased() {
            case "leave", "personal_leave": return "请假"
            case "business_trip":          return "出差"
            case "field_work":             return "外勤"
            default:
                if att.clockOut != nil { return "已下班" }
                if att.clockIn != nil  { return "已打卡" }
                return "未打卡"
            }
        }

        public var clockInText: String {
            guard let date = attendance?.clockIn else { return "--:--" }
            return Row.hhmmFormatter.string(from: date)
        }
        public var clockOutText: String {
            guard let date = attendance?.clockOut else { return "--:--" }
            return Row.hhmmFormatter.string(from: date)
        }
    }

    // MARK: - Published state

    @Published public private(set) var rows: [Row] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var searchQuery: String = ""
    @Published public var selectedDate: Date = Date()
    @Published public var departmentFilter: String? = nil

    /// 防止初始化阶段重复 fire load —— 避免 NavigationLink eager destination
    /// + .task 多次触发的双重拉取浪费请求。
    private var hasLoadedOnce: Bool = false
    /// 当前进行中的 load Task —— 避免 race 时数据被旧响应覆盖
    private var inFlight: Task<Void, Never>?

    public var allDepartments: [String] {
        Array(Set(rows.compactMap { $0.profile.department?.isEmpty == false ? $0.profile.department : nil })).sorted()
    }

    public var filteredRows: [Row] {
        var result = rows
        if let dept = departmentFilter, !dept.isEmpty {
            result = result.filter { $0.profile.department == dept }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { row in
                (row.profile.fullName?.localizedCaseInsensitiveContains(q) ?? false) ||
                (row.profile.displayName?.localizedCaseInsensitiveContains(q) ?? false) ||
                (row.profile.department?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return result
    }

    public var presentCount: Int {
        rows.filter { $0.attendance?.clockIn != nil }.count
    }
    public var absentCount: Int { rows.count - presentCount }

    // MARK: - Fetch

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
        // v1.5 修复"全员考勤经常需要手动刷新才出现"——
        // 原因复盘：BsCommandPalette 用 NavigationLink(destination:) eager 构造，
        // VM @StateObject 在 palette 列表 render 时就 init 一次。.task(id:) 后来
        // 在真正 push 出来的可见实例上是否 fire 是 SwiftUI 私有 lifecycle 决定 ——
        // 实测在 iOS 18+ NavStack 下 phantom 实例的 .task 会被 cancel，但 SwiftUI
        // 在某些 view-identity 复用路径上 .task(id:) 不会重 fire。
        //
        // 现在策略：VM init 立刻 kick off 一次 prefetch。即使 phantom 实例被丢，
        // SwiftUI 也会保留同一个 @StateObject（identity 复用），rows 数据被
        // populate 后真正可见的实例首帧就有数据。幂等：performLoad 内部 cancel
        // 旧 inFlight，多次 fire 不会浪费请求。
        Task { [weak self] in
            await self?.load()
        }
    }

    /// 首次进入：如果还没拉过、且 rows 为空，才触发 load。
    /// 与 init 的 prefetch 配合作为兜底 —— 如果 prefetch 因 auth/network
    /// 还没就绪而 silent fail，view appear 时这条会再补一发。
    public func loadIfNeeded() async {
        if hasLoadedOnce && !rows.isEmpty { return }
        await load()
    }

    public func load() async {
        // Cancel 旧请求 —— 防止用户快速切日期时旧响应覆盖新响应
        inFlight?.cancel()
        let task = Task { @MainActor [weak self] in
            // 显式 Void 返回 —— optional chaining 会让闭包推断成 () ?,
            // 与 inFlight: Task<Void, Never> 类型不兼容,显式包一层修。
            await self?.performLoad()
            return ()
        }
        inFlight = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let dateStr = Self.isoDate(selectedDate)

        do {
            // 1. 拉所有活跃员工
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .neq("status", value: "inactive")
                .order("full_name", ascending: true)
                .execute()
                .value

            try Task.checkCancellation()

            // 2. 拉指定日期所有打卡记录
            let attendances: [Attendance] = try await client
                .from("attendance")
                .select()
                .eq("date", value: dateStr)
                .execute()
                .value

            try Task.checkCancellation()

            // 3. 合并：一个 profile 最多一条 attendance
            let attMap: [UUID: Attendance] = Dictionary(uniqueKeysWithValues: attendances.map { ($0.userId, $0) })

            let merged: [Row] = profiles.map { p in
                Row(id: p.id, profile: p, attendance: attMap[p.id])
            }

            self.rows = merged
            self.hasLoadedOnce = true
        } catch is CancellationError {
            // 用户切了日期；下一次 load 会正常补上
        } catch {
            #if DEBUG
            print("[TeamAttendanceVM] load failed — type: \(type(of: error)), detail:", error)
            #endif
            self.errorMessage = "加载失败：\(ErrorLocalizer.localize(error))"
        }
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }
}
