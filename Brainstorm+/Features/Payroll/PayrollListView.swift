import SwiftUI
import Combine

public struct PayrollListView: View {
    @StateObject private var viewModel: PayrollListViewModel
    @Environment(SessionManager.self) private var sessionManager
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    /// Editor sheet state — when non-nil the sheet is presented.
    /// `nil` inside `.create` means new record path; `nil` outer means
    /// sheet is dismissed. Using an enum avoids the "two bools + one
    /// optional row" sheet state soup.
    @State private var editorTarget: EditorTarget? = nil
    @State private var pendingDelete: PayrollRecord? = nil

    private enum EditorTarget: Identifiable {
        case create
        case edit(PayrollRecord)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let p): return p.id.uuidString
            }
        }
    }

    public init(viewModel: PayrollListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            } else if viewModel.payrolls.isEmpty {
                VStack(spacing: BsSpacing.md) {
                    if viewModel.canViewAll {
                        scopePicker
                            .padding(.horizontal)
                            .padding(.top, BsSpacing.sm)
                    }
                    Spacer(minLength: 0)
                    BsEmptyState(
                        title: emptyTitle,
                        systemImage: "yensign.arrow.circlepath",
                        description: emptyDescription
                    )
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: BsSpacing.lg) {
                        if viewModel.canViewAll {
                            scopePicker
                                .padding(.horizontal)
                                .padding(.top, BsSpacing.xs)
                        }
                        ForEach(viewModel.payrolls) { payroll in
                            PayrollCardView(payroll: payroll)
                                .padding(.horizontal)
                                .modifier(AdminRowActions(
                                    isEnabled: viewModel.canEdit,
                                    onEdit: {
                                        // Haptic removed: 用户反馈菜单选项过密震动
                                        editorTarget = .edit(payroll)
                                    },
                                    onDelete: {
                                        // Haptic removed: 仅打开 confirm dialog，非真删
                                        pendingDelete = payroll
                                    }
                                ))
                        }
                    }
                    .padding(.vertical)
                }
                .background(BsColor.pageBackground)
            }
        }
        .navigationTitle("薪资")
        .toolbar {
            // "+" only makes sense when viewing the cross-employee list —
            // in `.mine` scope finance ops would be creating a row for
            // themselves, which is almost never the intent.
            if viewModel.canEdit && viewModel.scope == .all {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Haptic removed: 用户反馈 toolbar 按钮过密震动
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(BsColor.brandAzure)
                    .accessibilityLabel("新建薪资记录")
                }
            }
        }
        .refreshable {
            viewModel.bind(sessionProfile: sessionManager.currentProfile)
            await viewModel.fetchPayrolls()
        }
        .task {
            viewModel.bind(sessionProfile: sessionManager.currentProfile)
            await viewModel.fetchPayrolls()
        }
        .onChange(of: sessionManager.currentProfile?.id) { _, _ in
            viewModel.bind(sessionProfile: sessionManager.currentProfile)
        }
        .alert("加载失败", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .sheet(item: $editorTarget) { target in
            Group {
                switch target {
                case .create:
                    PayrollEditSheet(
                        viewModel: viewModel,
                        payroll: nil,
                        onDismiss: { editorTarget = nil }
                    )
                case .edit(let payroll):
                    PayrollEditSheet(
                        viewModel: viewModel,
                        payroll: payroll,
                        onDismiss: { editorTarget = nil }
                    )
                }
            }
            .bsSheetStyle(.form)
        }
        .confirmationDialog(
            "删除这条薪资记录？",
            isPresented: .init(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { payroll in
            Button("删除", role: .destructive) {
                let target = payroll
                pendingDelete = nil
                Task { @MainActor in
                    let ok = await viewModel.adminDeletePayroll(
                        id: target.id,
                        userId: target.userId,
                        period: target.period
                    )
                    if ok {
                        Haptic.warning() // destructive 真删确认完成
                    } else {
                        Haptic.warning()
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("删除后需重新导入或计算，确认？")
        }
    }

    // ── Scope picker (finance_ops / admin-tier only) ──
    private var scopePicker: some View {
        Picker("查看范围", selection: Binding(
            get: { viewModel.scope },
            set: { newValue in
                // Haptic removed: 用户反馈 picker 切换过密震动
                Task { await viewModel.setScope(newValue) }
            }
        )) {
            Text("我的").tag(PayrollScope.mine)
            Text("全部").tag(PayrollScope.all)
        }
        .pickerStyle(.segmented)
        .tint(BsColor.brandAzure)
    }

    private var emptyTitle: String {
        viewModel.scope == .all ? "暂无薪资记录" : "暂无薪资记录"
    }

    private var emptyDescription: String {
        viewModel.scope == .all
            ? "当前还没有任何员工的薪资记录。"
            : "你还没有任何薪资历史记录。"
    }

}

// ══════════════════════════════════════════════════════════════════
// AdminRowActions
// ──────────────────────────────────────────────────────────────────
// Attaches admin affordances (edit + delete) to a payroll row for
// finance_ops / admin viewers. No-op when `isEnabled` is false so
// ordinary employees see the card as a plain static row.
//
// Surfaces:
//   • `.contextMenu`  — long-press opens edit / delete (works in
//      `ScrollView + LazyVStack` contexts, which is what this screen uses).
//   • `.swipeActions` — attached for forward compat if this list ever
//      moves into a `List`; SwiftUI silently no-ops swipe actions
//      outside `List`, so keeping the declaration costs nothing.
// ══════════════════════════════════════════════════════════════════

private struct AdminRowActions: ViewModifier {
    let isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contextMenu {
                    Button {
                        onEdit()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        onEdit()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(BsColor.brandAzure)
                }
        } else {
            content
        }
    }
}
