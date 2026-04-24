import SwiftUI
import Combine

public struct PayrollListView: View {
    @StateObject private var viewModel: PayrollListViewModel
    @Environment(SessionManager.self) private var sessionManager
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    @State private var showAdminCreateSheet: Bool = false

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
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "yensign.arrow.circlepath",
                        description: Text(emptyDescription)
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
                        }
                    }
                    .padding(.vertical)
                }
                .background(BsColor.pageBackground)
            }
        }
        .navigationTitle("薪资")
        .toolbar {
            if viewModel.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdminCreateSheet = true
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
        .sheet(isPresented: $showAdminCreateSheet) {
            adminCreatePlaceholder
        }
    }

    // ── Scope picker (finance_ops / admin-tier only) ──
    private var scopePicker: some View {
        Picker("查看范围", selection: Binding(
            get: { viewModel.scope },
            set: { newValue in
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

    // Placeholder create sheet for admin. Full edit form is a
    // follow-up — for now we surface a clear TODO so the entry
    // point is wired end-to-end.
    private var adminCreatePlaceholder: some View {
        NavigationStack {
            VStack(spacing: BsSpacing.lg) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BsColor.inkMuted)
                Text("admin 新建薪资记录 (TODO)")
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                Text("此界面将在后续版本提供：按员工创建或批量导入薪资条。当前仅打通入口。")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BsColor.pageBackground)
            .navigationTitle("新建薪资")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showAdminCreateSheet = false }
                        .tint(BsColor.brandAzure)
                }
            }
        }
    }
}
