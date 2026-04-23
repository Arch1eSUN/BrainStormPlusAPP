import SwiftUI
import Combine

public struct PayrollListView: View {
    @StateObject private var viewModel: PayrollListViewModel
    
    public init(viewModel: PayrollListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
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
}
