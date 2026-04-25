import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Iter5 — 全员日报 / 周报聚合视图
// 用户反馈："全员的日报和周报我在哪里看"。
// 之前没有 admin 视角的聚合入口,管理员只能看到自己写的报告。
// 本视图按 RLS 拉取（admin / hr / superadmin 在 daily_logs / weekly_reports
// 上有 SELECT 权限,见 supabase/schema.sql 对应 policy）。
// 提供 segmented 切换日报/周报 + 成员筛选 + 日期范围。
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AdminTeamReportsViewModel: ObservableObject {
    public enum Segment: String, CaseIterable, Identifiable {
        case daily, weekly
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .daily: return "日报"
            case .weekly: return "周报"
            }
        }
    }

    public struct AuthorInfo: Hashable {
        public let id: UUID
        public let fullName: String
        public let department: String?
    }

    public struct DailyRow: Identifiable, Hashable {
        public let log: DailyLog
        public let author: AuthorInfo?
        public var id: UUID { log.id }
    }

    public struct WeeklyRow: Identifiable, Hashable {
        public let report: WeeklyReport
        public let author: AuthorInfo?
        public var id: UUID { report.id }
    }

    @Published public var segment: Segment = .daily
    @Published public var memberFilter: UUID? = nil // nil = 全部
    // iter7 fix (用户反馈"不需要做日期筛选 直接显示所有"):
    // 拿掉 rangeStart/rangeEnd state,直接抓最近 200 条所有可见报告 + RLS。

    @Published public private(set) var members: [AuthorInfo] = []
    @Published public private(set) var dailyRows: [DailyRow] = []
    @Published public private(set) var weeklyRows: [WeeklyRow] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    // MARK: - Date grouping (iter7 §A.3 — 全员日报按日期分组)

    /// Bucket label 顺序: 今天 → 昨天 → 本周内具体日期 → 更早。
    public struct DailyDateGroup: Identifiable {
        public let id: String
        public let label: String
        public let rows: [DailyRow]
    }

    public struct WeeklyDateGroup: Identifiable {
        public let id: String
        public let label: String
        public let rows: [WeeklyRow]
    }

    public var dailyGroups: [DailyDateGroup] {
        groupDailyByDate(dailyRows)
    }

    public var weeklyGroups: [WeeklyDateGroup] {
        groupWeeklyByDate(weeklyRows)
    }

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch segment {
            case .daily:
                try await loadDaily()
            case .weekly:
                try await loadWeekly()
            }
        } catch {
            // iter6 §A.5 — CancellationError 静默：用户在筛选/日期切换时
            // 旧 task 会被 SwiftUI .task(id:) 取消。
            let (tier, msg) = ErrorPresenter.present(error)
            if tier == .silent { return }
            errorMessage = msg
        }
    }

    private func loadDaily() async throws {
        struct Row: Decodable {
            let id: UUID
            let userId: UUID
            let date: Date
            let content: String
            let progress: String?
            let blockers: String?
            let createdAt: Date?
            let profiles: ProfileNested?
            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case date, content, progress, blockers
                case createdAt = "created_at"
                case profiles
            }
        }
        struct ProfileNested: Decodable {
            let id: UUID
            let fullName: String?
            let department: String?
            enum CodingKeys: String, CodingKey {
                case id
                case fullName = "full_name"
                case department
            }
        }

        var query = client
            .from("daily_logs")
            .select("id, user_id, date, content, progress, blockers, created_at, profiles:user_id(id, full_name, department)")

        if let uid = memberFilter {
            query = query.eq("user_id", value: uid.uuidString)
        }

        let rows: [Row] = try await query
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value

        dailyRows = rows.map { r in
            let log = DailyLog(
                id: r.id,
                userId: r.userId,
                date: r.date,
                content: r.content,
                progress: r.progress,
                blockers: r.blockers,
                createdAt: r.createdAt
            )
            let author = r.profiles.map {
                AuthorInfo(id: $0.id, fullName: $0.fullName ?? "未命名", department: $0.department)
            }
            return DailyRow(log: log, author: author)
        }

        // Refresh members list for the filter chip strip from the loaded rows.
        let extracted = rows.compactMap { row -> AuthorInfo? in
            guard let p = row.profiles else { return nil }
            return AuthorInfo(id: p.id, fullName: p.fullName ?? "未命名", department: p.department)
        }
        var seen: Set<UUID> = []
        var unique: [AuthorInfo] = []
        for m in extracted where seen.insert(m.id).inserted {
            unique.append(m)
        }
        if !unique.isEmpty {
            members = unique.sorted { $0.fullName < $1.fullName }
        }
    }

    private func loadWeekly() async throws {
        struct Row: Decodable {
            let id: UUID
            let userId: UUID
            let weekStart: Date
            let weekEnd: Date?
            let summary: String?
            let accomplishments: String?
            let plans: String?
            let blockers: String?
            let createdAt: Date?
            let profiles: ProfileNested?
            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case weekStart = "week_start"
                case weekEnd = "week_end"
                case summary, accomplishments, plans, blockers
                case createdAt = "created_at"
                case profiles
            }
        }
        struct ProfileNested: Decodable {
            let id: UUID
            let fullName: String?
            let department: String?
            enum CodingKeys: String, CodingKey {
                case id
                case fullName = "full_name"
                case department
            }
        }

        var query = client
            .from("weekly_reports")
            .select("id, user_id, week_start, week_end, summary, accomplishments, plans, blockers, created_at, profiles:user_id(id, full_name, department)")

        if let uid = memberFilter {
            query = query.eq("user_id", value: uid.uuidString)
        }

        let rows: [Row] = try await query
            .order("week_start", ascending: false)
            .limit(200)
            .execute()
            .value

        weeklyRows = rows.map { r in
            let report = WeeklyReport(
                id: r.id,
                userId: r.userId,
                weekStart: r.weekStart,
                weekEnd: r.weekEnd,
                summary: r.summary,
                accomplishments: r.accomplishments,
                plans: r.plans,
                blockers: r.blockers,
                createdAt: r.createdAt
            )
            let author = r.profiles.map {
                AuthorInfo(id: $0.id, fullName: $0.fullName ?? "未命名", department: $0.department)
            }
            return WeeklyRow(report: report, author: author)
        }

        let extracted = rows.compactMap { row -> AuthorInfo? in
            guard let p = row.profiles else { return nil }
            return AuthorInfo(id: p.id, fullName: p.fullName ?? "未命名", department: p.department)
        }
        var seen: Set<UUID> = []
        var unique: [AuthorInfo] = []
        for m in extracted where seen.insert(m.id).inserted {
            unique.append(m)
        }
        if !unique.isEmpty {
            members = unique.sorted { $0.fullName < $1.fullName }
        }
    }

    private func isoDay(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }

    // MARK: - Grouping helpers (iter7)
    //
    // 用户反馈"全员的日报按照每一天和日期分类好"。按日期 bucket → 同一
    // bucket 内按提交人姓名稳定排序。bucket label:
    //   • 今天 / 昨天   — 用户视角最相关
    //   • 本周内 → 周三 / 本周一 ...
    //   • 更早 → "M月d日"

    private func groupDailyByDate(_ rows: [DailyRow]) -> [DailyDateGroup] {
        let cal = Calendar(identifier: .gregorian)
        // 按 startOfDay(date) bucket
        let buckets = Dictionary(grouping: rows) { row -> Date in
            cal.startOfDay(for: row.log.date)
        }
        return buckets.keys.sorted(by: >).map { day in
            let label = relativeDateLabel(day, cal: cal)
            let id = isoDay(day)
            let sortedRows = (buckets[day] ?? []).sorted {
                ($0.author?.fullName ?? "") < ($1.author?.fullName ?? "")
            }
            return DailyDateGroup(id: id, label: label, rows: sortedRows)
        }
    }

    private func groupWeeklyByDate(_ rows: [WeeklyRow]) -> [WeeklyDateGroup] {
        let cal = Calendar(identifier: .gregorian)
        let buckets = Dictionary(grouping: rows) { row -> Date in
            cal.startOfDay(for: row.report.weekStart)
        }
        return buckets.keys.sorted(by: >).map { day in
            let label = relativeDateLabel(day, cal: cal)
            let id = isoDay(day)
            let sortedRows = (buckets[day] ?? []).sorted {
                ($0.author?.fullName ?? "") < ($1.author?.fullName ?? "")
            }
            return WeeklyDateGroup(id: id, label: label, rows: sortedRows)
        }
    }

    private func relativeDateLabel(_ day: Date, cal: Calendar) -> String {
        if cal.isDateInToday(day) { return "今天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        let now = Date()
        if cal.isDate(day, equalTo: now, toGranularity: .weekOfYear) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "EEEE" // 周三
            return "本" + f.string(from: day)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: day)
    }
}

public struct AdminTeamReportsView: View {
    @StateObject private var vm = AdminTeamReportsViewModel()

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
        VStack(spacing: 0) {
            controlsCard
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.sm)
                .padding(.bottom, BsSpacing.md)

            // Iter 7 §C.1 — skeleton-first via bsLoadingState。List 始终挂载,
            // 首屏 redacted+shimmer 给"骨架屏",empty 走 design-system 统一 chrome。
            List {
                switch vm.segment {
                case .daily:
                    ForEach(vm.dailyGroups) { group in
                        Section(group.label) {
                            ForEach(group.rows) { row in
                                dailyCard(row)
                                    .listRowInsets(EdgeInsets(top: 6, leading: BsSpacing.lg, bottom: 6, trailing: BsSpacing.lg))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                case .weekly:
                    ForEach(vm.weeklyGroups) { group in
                        Section(group.label) {
                            ForEach(group.rows) { row in
                                weeklyCard(row)
                                    .listRowInsets(EdgeInsets(top: 6, leading: BsSpacing.lg, bottom: 6, trailing: BsSpacing.lg))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .bsLoadingState(BsLoadingState.derive(
                isLoading: vm.isLoading,
                hasItems: !currentRowsEmpty,
                errorMessage: nil,                              // banner 走 zyErrorBanner
                emptySystemImage: vm.segment == .daily ? "doc.text" : "calendar",
                emptyTitle: "暂无报告",
                emptyDescription: "调整成员或日期范围试试"
            ))
            .animation(.smooth(duration: 0.25), value: vm.dailyGroups.count + vm.weeklyGroups.count)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("全员日报 / 周报")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onChange(of: vm.segment) { _, _ in Task { await vm.load() } }
        .onChange(of: vm.memberFilter) { _, _ in Task { await vm.load() } }
        .zyErrorBanner($vm.errorMessage)
    }

    private var currentRowsEmpty: Bool {
        switch vm.segment {
        case .daily: return vm.dailyRows.isEmpty
        case .weekly: return vm.weeklyRows.isEmpty
        }
    }

    private var controlsCard: some View {
        // iter7 fix: 拿掉日期 range pickers (用户反馈"上面两栏筛选好奇怪 /
        // 不需要做日期筛选 直接显示所有"); 仅保留 segmented + 人员筛选 Menu。
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                Picker("视图", selection: $vm.segment) {
                    ForEach(AdminTeamReportsViewModel.Segment.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                memberFilterMenu
            }
        }
    }

    @ViewBuilder
    private var memberFilterMenu: some View {
        // iter7 §A.3 — iOS-native Menu+Picker (与 ReportingListView 同款)。
        let selectedLabel: String = {
            if let uid = vm.memberFilter,
               let m = vm.members.first(where: { $0.id == uid }) {
                return m.fullName
            }
            return "全部成员"
        }()
        Menu {
            Picker("成员", selection: $vm.memberFilter) {
                Text("全部成员").tag(UUID?.none)
                ForEach(vm.members, id: \.id) { m in
                    if let dept = m.department, !dept.isEmpty {
                        Text("\(m.fullName) · \(dept)").tag(UUID?.some(m.id))
                    } else {
                        Text(m.fullName).tag(UUID?.some(m.id))
                    }
                }
            }
        } label: {
            HStack {
                Label(selectedLabel, systemImage: "person.2.fill")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(BsColor.inkFaint)
            }
            .padding(.horizontal, BsSpacing.md)
            .padding(.vertical, BsSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BsColor.inkMuted.opacity(0.08))
            )
        }
    }

    @ViewBuilder
    private func dailyCard(_ row: AdminTeamReportsViewModel.DailyRow) -> some View {
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    Text(row.author?.fullName ?? "未知作者")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if let dept = row.author?.department, !dept.isEmpty {
                        Text(dept)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Text(formatDate(row.log.date))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Text(row.log.content)
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = row.log.progress, !progress.isEmpty {
                    Label(progress, systemImage: "checkmark.circle")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.success)
                }
                if let blockers = row.log.blockers, !blockers.isEmpty {
                    Label(blockers, systemImage: "exclamationmark.triangle")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func weeklyCard(_ row: AdminTeamReportsViewModel.WeeklyRow) -> some View {
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    Text(row.author?.fullName ?? "未知作者")
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    if let dept = row.author?.department, !dept.isEmpty {
                        Text(dept)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer()
                    Text(formatWeekRange(start: row.report.weekStart, end: row.report.weekEnd))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if let summary = row.report.summary, !summary.isEmpty {
                    Text(summary)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(8)
                }
                if let acc = row.report.accomplishments, !acc.isEmpty {
                    Text("成就：\(acc)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.success)
                        .lineLimit(4)
                }
                if let plans = row.report.plans, !plans.isEmpty {
                    Text("计划：\(plans)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.brandAzure)
                        .lineLimit(4)
                }
                if let blockers = row.report.blockers, !blockers.isEmpty {
                    Text("阻碍：\(blockers)")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.warning)
                        .lineLimit(4)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM月dd日"
        return f.string(from: date)
    }

    private func formatWeekRange(start: Date, end: Date?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd"
        if let end = end {
            return "\(f.string(from: start)) - \(f.string(from: end))"
        }
        return f.string(from: start)
    }
}
