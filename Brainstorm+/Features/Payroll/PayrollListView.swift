import SwiftUI
import Combine

public struct PayrollListView: View {
    @StateObject private var viewModel: PayrollListViewModel
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

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
                ContentUnavailableView("暂无薪资记录", systemImage: "yensign.arrow.circlepath", description: Text("你还没有任何薪资历史记录。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: BsSpacing.lg) {
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
        .refreshable {
            await viewModel.fetchPayrolls()
        }
        .task {
            await viewModel.fetchPayrolls()
        }
        .alert("加载失败", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}
