import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// GlobalSearchSheet — Iter 8 P1 §B.3 (⌘K-style cross-module sheet)
//
// Slack/Mail-grade global search. Surfaced from MainTabView's
// magnifying-glass toolbar button; presents over the current tab as
// a `.large` detent sheet with thinMaterial bg.
//
// Layered query strategy:
//   1. Local fan-out RPC `public.global_search(q, module, limit)` —
//      one round-trip, all modules in parallel (each branch internally
//      ranked by created_at desc with FTS + ilike fallback).
//   2. Tab segmented picker filters which module rows to show. The
//      RPC is fired once per input change (debounced ~250ms), the
//      response is cached locally, and tab switching is instant.
//
// Why we don't fire one RPC per tab:
//   • The unified RPC is bounded by p_limit, so worst-case payload
//     is ~30 rows × 8 modules ≈ 240 rows — cheap.
//   • Slack/Mail switch tabs instantly; per-tab refetch would feel
//     laggy at the network edge.
//
// Navigation: tapping a row dismisses the sheet, then publishes a
// `GlobalSearchNavigation` notification on the default center. The
// MainTabView listens, switches the relevant tab, and scrolls to the
// row in question. (Tab-internal deep links — opening a specific
// approval / task by id — are P2; today we just land the user on the
// right tab so they can scroll/filter from there.)
// ══════════════════════════════════════════════════════════════════

/// Modules surfaced in the segmented picker. Mirrors the RPC's
/// `p_module` enum + display labels.
public enum GlobalSearchModule: String, CaseIterable, Identifiable, Hashable {
    case all
    case task
    case approval
    case message
    case daily
    case weekly
    case announcement
    case project
    case person

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:          return "全部"
        case .task:         return "任务"
        case .approval:     return "审批"
        case .message:      return "消息"
        case .daily:        return "日报"
        case .weekly:       return "周报"
        case .announcement: return "公告"
        case .project:      return "项目"
        case .person:       return "人员"
        }
    }

    public var systemIcon: String {
        switch self {
        case .all:          return "magnifyingglass"
        case .task:         return "checkmark.square"
        case .approval:     return "checkmark.seal"
        case .message:      return "bubble.left"
        case .daily:        return "doc.text"
        case .weekly:       return "calendar"
        case .announcement: return "megaphone"
        case .project:      return "folder"
        case .person:       return "person.crop.circle"
        }
    }
}

/// Decoded row from the `global_search` RPC.
public struct GlobalSearchRow: Identifiable, Decodable, Hashable {
    public let module: String
    public let itemId: UUID
    public let title: String
    public let snippet: String?
    public let createdAt: Date?

    public var id: String { "\(module)-\(itemId.uuidString)" }

    public var moduleEnum: GlobalSearchModule {
        GlobalSearchModule(rawValue: module) ?? .all
    }

    enum CodingKeys: String, CodingKey {
        case module
        case itemId    = "item_id"
        case title
        case snippet
        case createdAt = "created_at"
    }
}

/// Notification posted when a row is tapped — MainTabView listens and
/// switches the active tab. We use NotificationCenter rather than a
/// new SessionManager dependency to keep this sheet decoupled from
/// the tab routing internals.
public extension Notification.Name {
    static let globalSearchNavigate = Notification.Name("globalSearchNavigate")
}

@MainActor
public final class GlobalSearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var selectedModule: GlobalSearchModule = .all
    @Published public private(set) var rows: [GlobalSearchRow] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient
    private var searchTask: Task<Void, Never>?

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Filtered rows for the active tab — `all` shows everything; per-
    /// module tabs filter the cached payload.
    public var visibleRows: [GlobalSearchRow] {
        guard selectedModule != .all else { return rows }
        return rows.filter { $0.moduleEnum == selectedModule }
    }

    /// Group rows by module for the `all` view (mirrors Slack's
    /// "in messages / in files / in people" sections).
    public var groupedAll: [(GlobalSearchModule, [GlobalSearchRow])] {
        let order: [GlobalSearchModule] = [
            .task, .approval, .message, .daily, .weekly,
            .announcement, .project, .person
        ]
        return order.compactMap { mod in
            let r = rows.filter { $0.moduleEnum == mod }
            return r.isEmpty ? nil : (mod, r)
        }
    }

    /// Debounced search — cancels in-flight task on each keystroke,
    /// fires after ~250ms idle. Empty query clears the result set
    /// without hitting the network.
    public func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            rows = []
            isLoading = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.runSearch(q: q)
        }
    }

    private func runSearch(q: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct Params: Encodable {
            let p_query: String
            let p_module: String
            let p_limit: Int
        }

        do {
            let result: [GlobalSearchRow] = try await client
                .rpc("global_search", params: Params(
                    p_query: q,
                    p_module: "all",   // always fetch all, filter locally per tab
                    p_limit: 30
                ))
                .execute()
                .value
            // Drop stale results if a newer search has started.
            guard !Task.isCancelled else { return }
            self.rows = result
        } catch {
            // Soft-fail — show empty state with banner. Don't dismiss
            // the sheet; user might just retry with a different query.
            self.errorMessage = ErrorLocalizer.localize(error)
            self.rows = []
        }
    }
}

// MARK: - View

public struct GlobalSearchSheet: View {
    @StateObject private var viewModel: GlobalSearchViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    public init(client: SupabaseClient = supabase) {
        _viewModel = StateObject(wrappedValue: GlobalSearchViewModel(client: client))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                modulePicker
                resultsList
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            .navigationTitle("全局搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .tint(BsColor.brandAzure)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.thinMaterial)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BsColor.inkMuted)
            TextField("搜索任务、审批、消息、日报、公告、项目、人员…", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.scheduleSearch()
                }
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.scheduleSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var modulePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GlobalSearchModule.allCases) { mod in
                    let count = viewModel.rows.filter {
                        mod == .all || $0.moduleEnum == mod
                    }.count
                    Button {
                        viewModel.selectedModule = mod
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mod.systemIcon)
                                .font(.system(size: 12, weight: .medium))
                            Text(mod.label)
                                .font(.system(size: 13, weight: .medium))
                            if mod == .all || count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(viewModel.selectedModule == mod ? .white.opacity(0.8) : BsColor.inkMuted)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                viewModel.selectedModule == mod
                                    ? BsColor.brandAzure
                                    : BsColor.surfacePrimary
                            )
                        )
                        .foregroundStyle(
                            viewModel.selectedModule == mod ? .white : BsColor.ink
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            placeholderView
        } else if viewModel.visibleRows.isEmpty && !viewModel.isLoading {
            emptyView
        } else if viewModel.selectedModule == .all {
            groupedList
        } else {
            flatList
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(BsColor.inkMuted)
            Text("输入关键词搜索")
                .foregroundStyle(BsColor.ink)
            Text("支持任务 / 审批 / 消息 / 日报 / 周报 / 公告 / 项目 / 人员")
                .font(.footnote)
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("没有找到「\(viewModel.query)」相关结果")
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedList: some View {
        List {
            ForEach(viewModel.groupedAll, id: \.0) { (mod, items) in
                Section(header: HStack {
                    Image(systemName: mod.systemIcon).font(.caption)
                    Text(mod.label).font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(items.count)").font(.caption2).foregroundStyle(BsColor.inkMuted)
                }) {
                    ForEach(items) { row in
                        rowView(row)
                            .listRowBackground(BsColor.surfacePrimary)
                    }
                }
            }
            if let err = viewModel.errorMessage {
                Section {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var flatList: some View {
        List {
            ForEach(viewModel.visibleRows) { row in
                rowView(row)
                    .listRowBackground(BsColor.surfacePrimary)
            }
            if let err = viewModel.errorMessage {
                Section {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowView(_ row: GlobalSearchRow) -> some View {
        Button {
            navigate(to: row)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.moduleEnum.systemIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BsColor.brandAzure)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                    if let s = row.snippet, !s.isEmpty {
                        Text(s)
                            .font(.system(size: 12))
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(row.moduleEnum.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(BsColor.brandAzure.opacity(0.1))
                            )
                            .foregroundStyle(BsColor.brandAzure)
                        if let date = row.createdAt {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10))
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navigate(to row: GlobalSearchRow) {
        // Dismiss first so the destination tab's sheet stack stays clean.
        dismiss()
        NotificationCenter.default.post(
            name: .globalSearchNavigate,
            object: nil,
            userInfo: [
                "module": row.module,
                "itemId": row.itemId.uuidString
            ]
        )
    }
}
