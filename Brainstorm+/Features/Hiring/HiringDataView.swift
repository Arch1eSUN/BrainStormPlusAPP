import SwiftUI
import Combine
import Supabase

// Phase 4.4 — combined read view for hiring-adjacent tables.
// Web exposes full CRUD for contracts + seniority on the same page,
// but those tables are backed by HR Ops authorial workflows which
// are deferred on iOS (interview records table not modeled). The
// data tab surfaces the current DB snapshot so HR can verify state
// on the go; authoring stays on Web.

@MainActor
public final class HiringDataViewModel: ObservableObject {
    @Published public private(set) var contracts: [HiringContract] = []
    @Published public private(set) var seniority: [SeniorityRecord] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    public init() {}

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // iter7 fix (用户反馈"招聘管理的数据那里显示 contracts 和
            // userid 在 schema cache 没有 relationship"):
            //
            // 根因: contracts.user_id / seniority_records.user_id FK 都指向
            // auth.users(id) 而非 public.profiles(id) — 见 005_hiring_*.sql
            // line 42 / 58。PostgREST schema cache 找不到 contracts→profiles
            // 的 FK 关系 → 嵌入语法 `profiles:user_id(...)` 直接 PGRST200
            // schema cache miss。
            //
            // 兜底: 不走 PostgREST embedding,先抓 contracts/seniority,再
            // 用 .in() 一次性 batch-fetch 涉及到的 profiles, 客户端 stitch。
            // (auth.users.id == public.profiles.id 1:1 by design 见
            //  001_rbac_multi_tenant.sql)。
            //
            // 长期解: 见 /tmp/bs-parked-migrations/<date>_hiring_profiles_fk.sql
            // 加 FK from contracts.user_id → public.profiles(id) ON DELETE
            // SET NULL,然后 PostgREST 重载 schema 后嵌入语法可正常用。
            async let contractRowsRaw: [HiringContract] = supabase
                .from("contracts")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            async let seniorityRowsRaw: [SeniorityRecord] = supabase
                .from("seniority_records")
                .select()
                .order("hire_date", ascending: false)
                .execute()
                .value

            let cs = try await contractRowsRaw
            let ss = try await seniorityRowsRaw

            // Collect the union of user_ids,一次性查 profiles。
            var allUserIds: Set<UUID> = []
            for c in cs { if let uid = c.userId { allUserIds.insert(uid) } }
            for s in ss { if let uid = s.userId { allUserIds.insert(uid) } }

            var profilesById: [UUID: HiringContract.LinkedProfile] = [:]
            if !allUserIds.isEmpty {
                struct ProfileRow: Decodable {
                    let id: UUID
                    let fullName: String?
                    let displayName: String?
                    enum CodingKeys: String, CodingKey {
                        case id
                        case fullName = "full_name"
                        case displayName = "display_name"
                    }
                }
                let idList = allUserIds.map { $0.uuidString }
                let rows: [ProfileRow] = try await supabase
                    .from("profiles")
                    .select("id, full_name, display_name")
                    .in("id", values: idList)
                    .execute()
                    .value
                for r in rows {
                    profilesById[r.id] = HiringContract.LinkedProfile(
                        fullName: r.fullName,
                        displayName: r.displayName
                    )
                }
            }

            // Stitch: copy and inject profiles。
            contracts = cs.map { c in
                var copy = c
                if let uid = c.userId { copy.profiles = profilesById[uid] }
                return copy
            }
            seniority = ss.map { s in
                var copy = s
                if let uid = s.userId { copy.profiles = profilesById[uid] }
                return copy
            }
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }
}

public struct HiringDataView: View {
    @StateObject private var viewModel = HiringDataViewModel()
    @State private var selectedSection: Section = .contracts

    public init() {}

    public enum Section: String, CaseIterable, Identifiable {
        case contracts
        case seniority

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .contracts: return "合同"
            case .seniority: return "职级"
            }
        }
    }

    public var body: some View {
        // Bug-fix(Hiring tab jump): 同 HiringCenterView，picker 固定顶部，
        // loading/empty 子 view 撑满高度避免高度坍塌引起 nav bar / 外层 picker 跳动。
        VStack(spacing: 0) {
            Picker("数据", selection: $selectedSection) {
                ForEach(Section.allCases) { s in Text(s.title).tag(s) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            // Haptic removed: 用户反馈 picker 切换过密震动

            Group {
                if viewModel.isLoading && viewModel.contracts.isEmpty && viewModel.seniority.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    switch selectedSection {
                    case .contracts: contractsList
                    case .seniority: seniorityList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private var contractsList: some View {
        if viewModel.contracts.isEmpty {
            BsEmptyState(
                title: "暂无合同记录",
                systemImage: "doc.text",
                description: "合同的新建/编辑当前只在 Web 端提供。"
            )
        } else {
            List {
                ForEach(viewModel.contracts) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(c.contractType.displayLabel)
                                .font(.headline)
                            Spacer()
                            badge(c.status.displayLabel, tint: color(for: c.status))
                        }
                        if let name = employeeName(from: c.profiles) {
                            Label(name, systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        HStack(spacing: 8) {
                            Label(periodText(start: c.startDate, end: c.endDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
                            if let salary = c.salary {
                                Label("¥\(formatMoney(salary))", systemImage: "yensign.circle")
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                        if let notes = c.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkMuted)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var seniorityList: some View {
        if viewModel.seniority.isEmpty {
            BsEmptyState(
                title: "暂无职级记录",
                systemImage: "award",
                description: "职级记录的新建/编辑当前只在 Web 端提供。"
            )
        } else {
            List {
                ForEach(viewModel.seniority) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.hireDate)
                                .font(.headline)
                            Spacer()
                            if let level = s.level, !level.isEmpty {
                                badge(level, tint: BsColor.brandAzure)
                            }
                        }
                        if let name = employeeName(from: s.profiles) {
                            Label("\(name) · 工龄 \(daysSince(s.hireDate)) 天", systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        HStack(spacing: 8) {
                            if let dept = s.department, !dept.isEmpty {
                                Label(dept, systemImage: "building.2")
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                            if let pos = s.position, !pos.isEmpty {
                                Label(pos, systemImage: "briefcase")
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Formatting helpers

    private func employeeName(from profile: HiringContract.LinkedProfile?) -> String? {
        let raw = profile?.fullName?.trimmingCharacters(in: .whitespaces)
        if let raw, !raw.isEmpty { return raw }
        let alt = profile?.displayName?.trimmingCharacters(in: .whitespaces)
        if let alt, !alt.isEmpty { return alt }
        return nil
    }

    private func periodText(start: String, end: String?) -> String {
        guard let end, !end.isEmpty else {
            return "\(start) → 至今"
        }
        return "\(start) → \(end)"
    }

    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func daysSince(_ isoDate: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: isoDate) else { return 0 }
        let seconds = Date().timeIntervalSince(date)
        return max(0, Int(seconds / 86_400))
    }

    private func color(for status: HiringContract.ContractStatus) -> Color {
        switch status {
        case .active:     return BsColor.success
        case .pending:    return BsColor.warning
        case .expired:    return BsColor.inkMuted
        case .terminated: return BsColor.danger
        }
    }

    @ViewBuilder
    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
