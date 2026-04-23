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
            async let contractRows: [HiringContract] = supabase
                .from("contracts")
                .select("*, profiles:user_id(full_name, display_name)")
                .order("created_at", ascending: false)
                .execute()
                .value
            async let seniorityRows: [SeniorityRecord] = supabase
                .from("seniority_records")
                .select("*, profiles:user_id(full_name, display_name)")
                .order("hire_date", ascending: false)
                .execute()
                .value
            contracts = try await contractRows
            seniority = try await seniorityRows
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
        VStack(spacing: 0) {
            Picker("数据", selection: $selectedSection) {
                ForEach(Section.allCases) { s in Text(s.title).tag(s) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                if viewModel.isLoading && viewModel.contracts.isEmpty && viewModel.seniority.isEmpty {
                    ProgressView().padding(.top, 40)
                } else {
                    switch selectedSection {
                    case .contracts: contractsList
                    case .seniority: seniorityList
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private var contractsList: some View {
        if viewModel.contracts.isEmpty {
            ContentUnavailableView(
                "暂无合同记录",
                systemImage: "doc.text",
                description: Text("合同的新建/编辑当前只在 Web 端提供。")
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
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Label(periodText(start: c.startDate, end: c.endDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let salary = c.salary {
                                Label("¥\(formatMoney(salary))", systemImage: "yensign.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let notes = c.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
            ContentUnavailableView(
                "暂无职级记录",
                systemImage: "award",
                description: Text("职级记录的新建/编辑当前只在 Web 端提供。")
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
                                badge(level, tint: .blue)
                            }
                        }
                        if let name = employeeName(from: s.profiles) {
                            Label("\(name) · 工龄 \(daysSince(s.hireDate)) 天", systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if let dept = s.department, !dept.isEmpty {
                                Label(dept, systemImage: "building.2")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let pos = s.position, !pos.isEmpty {
                                Label(pos, systemImage: "briefcase")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        case .active:     return .green
        case .pending:    return .orange
        case .expired:    return .secondary
        case .terminated: return .red
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
