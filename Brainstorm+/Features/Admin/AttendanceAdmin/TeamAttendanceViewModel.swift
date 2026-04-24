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
    }

    public func load() async {
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

            // 2. 拉指定日期所有打卡记录
            let attendances: [Attendance] = try await client
                .from("attendance")
                .select()
                .eq("date", value: dateStr)
                .execute()
                .value

            // 3. 合并：一个 profile 最多一条 attendance
            let attMap: [UUID: Attendance] = Dictionary(uniqueKeysWithValues: attendances.map { ($0.userId, $0) })

            let merged: [Row] = profiles.map { p in
                Row(id: p.id, profile: p, attendance: attMap[p.id])
            }

            self.rows = merged
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
