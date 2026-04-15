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
                    ContentUnavailableView("No Payroll Records", systemImage: "yensign.arrow.circlepath", description: Text("You have no payroll history yet."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.payrolls) { payroll in
                                PayrollCardView(payroll: payroll)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Payroll")
            .refreshable {
                await viewModel.fetchPayrolls()
            }
            .task {
                await viewModel.fetchPayrolls()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}
