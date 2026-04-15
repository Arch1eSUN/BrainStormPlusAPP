import SwiftUI
import Combine

public struct ReportingListView: View {
    @StateObject private var viewModel: ReportingViewModel
    
    public init(viewModel: ReportingViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 24) {
                        if !viewModel.dailyLogs.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Recent Daily Logs")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                ForEach(viewModel.dailyLogs) { log in
                                    DailyLogCardView(log: log)
                                        .padding(.horizontal)
                                }
                            }
                        } else {
                            ContentUnavailableView("No Logs", systemImage: "doc.text", description: Text("Start journaling your daily progress."))
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Reporting")
            .refreshable {
                await viewModel.fetchReports()
            }
            .task {
                await viewModel.fetchReports()
            }
        }
    }
}
