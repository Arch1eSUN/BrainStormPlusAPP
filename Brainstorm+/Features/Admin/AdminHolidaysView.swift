import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 公休日历
// Parity target: Web `src/lib/actions/holidays.ts`（年视图简化版）。
// 直接读写 public_holiday_days；RLS 要求 holiday_admin capability 写入。
// iOS 提供按年列表 + 新增 + 删除；年视图日历 UI 留给 Web。
// ══════════════════════════════════════════════════════════════════

public struct HolidayRow: Decodable, Identifiable, Hashable {
    public let id: UUID
    public let holidayDate: String
    public let name: String
    public let region: String
    public let source: String
    public let isPaid: Bool
    public let isWorkDay: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case holidayDate = "holiday_date"
        case name
        case region
        case source
        case isPaid = "is_paid"
        case isWorkDay = "is_work_day"
    }
}

@MainActor
final class AdminHolidaysViewModel: ObservableObject {
    @Published var year: Int = {
        Calendar.current.component(.year, from: Date())
    }()
    @Published var rows: [HolidayRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let from = "\(year)-01-01"
            let to = "\(year)-12-31"
            let res: [HolidayRow] = try await client
                .from("public_holiday_days")
                .select("id, holiday_date, name, region, source, is_paid, is_work_day")
                .gte("holiday_date", value: from)
                .lte("holiday_date", value: to)
                .order("holiday_date", ascending: true)
                .execute()
                .value
            rows = res
        } catch {
            errorMessage = "加载公休日失败：\(ErrorLocalizer.localize(error))"
        }
    }

    struct InsertPayload: Encodable {
        let holiday_date: String
        let name: String
        let region: String
        let source: String
        let is_paid: Bool
        let is_work_day: Bool
    }

    func add(date: String, name: String, region: String, isPaid: Bool, isWorkDay: Bool) async -> Bool {
        do {
            let payload = InsertPayload(
                holiday_date: date,
                name: name,
                region: region,
                source: "custom",
                is_paid: isPaid,
                is_work_day: isWorkDay
            )
            _ = try await client
                .from("public_holiday_days")
                .upsert(payload, onConflict: "holiday_date,region,name")
                .execute()
            await load()
            return true
        } catch {
            errorMessage = "新增失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    func delete(id: UUID) async {
        do {
            _ = try await client
                .from("public_holiday_days")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            rows.removeAll { $0.id == id }
        } catch {
            errorMessage = "删除失败：\(ErrorLocalizer.localize(error))"
        }
    }
}

public struct AdminHolidaysView: View {
    @StateObject private var vm = AdminHolidaysViewModel()
    @State private var showAddSheet = false

    // Phase 3: isEmbedded parameterization
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
        List {
            Section {
                Stepper("年份：\(vm.year)", value: $vm.year, in: 2000...2100)
                    .onChange(of: vm.year) { _, _ in
                        Task { await vm.load() }
                    }
            }

            if vm.isLoading && vm.rows.isEmpty {
                // Bug-fix(loading 一致性): inline section loading 用 .small 圈。
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if vm.rows.isEmpty {
                Text("暂无该年份的公休记录")
                    .foregroundStyle(BsColor.inkMuted)
                    .font(.subheadline)
            } else {
                ForEach(vm.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.holidayDate).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(row.isWorkDay ? "调休上班" : (row.isPaid ? "带薪假" : "无薪假"))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(
                                    row.isWorkDay ? BsColor.warning.opacity(0.15)
                                    : (row.isPaid ? BsColor.success.opacity(0.15) : BsColor.inkMuted.opacity(0.15))
                                ))
                                .foregroundStyle(
                                    row.isWorkDay ? BsColor.warning
                                    : (row.isPaid ? BsColor.success : BsColor.inkMuted)
                                )
                        }
                        Text("\(row.name) · \(regionLabel(row.region)) · \(sourceLabel(row.source))")
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            // Haptic removed: swipe action 系统自带反馈
                            Task { await vm.delete(id: row.id) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("公休日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增公休")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            HolidayAddSheet { date, name, region, isPaid, isWorkDay in
                Task { _ = await vm.add(date: date, name: name, region: region, isPaid: isPaid, isWorkDay: isWorkDay) }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    private func regionLabel(_ r: String) -> String {
        switch r {
        case "national": return "全国"
        case "guangxi": return "广西"
        case "xinjiang": return "新疆"
        default: return r
        }
    }

    private func sourceLabel(_ s: String) -> String {
        switch s {
        case "gov": return "政府"
        case "regional": return "地方"
        case "custom": return "自定义"
        default: return s
        }
    }
}

private struct HolidayAddSheet: View {
    let onSubmit: (_ date: String, _ name: String, _ region: String, _ isPaid: Bool, _ isWorkDay: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = Date()
    @State private var name: String = ""
    @State private var region: String = "national"
    @State private var isPaid: Bool = true
    @State private var isWorkDay: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("假期名称", text: $name)
                    Picker("区域", selection: $region) {
                        Text("全国").tag("national")
                        Text("广西").tag("guangxi")
                        Text("新疆").tag("xinjiang")
                    }
                    Toggle("带薪", isOn: $isPaid)
                    Toggle("调休上班日", isOn: $isWorkDay)
                }
            }
            .navigationTitle("新增公休")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Haptic.medium()
                        let f = DateFormatter()
                        f.calendar = Calendar(identifier: .gregorian)
                        f.locale = Locale(identifier: "en_US_POSIX")
                        f.dateFormat = "yyyy-MM-dd"
                        let dateStr = f.string(from: date)
                        onSubmit(dateStr, name, region, isPaid, isWorkDay)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
