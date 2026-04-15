import SwiftUI
import Combine

public struct NotificationListView: View {
    @StateObject private var viewModel: NotificationListViewModel
    
    public init(viewModel: NotificationListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.notifications.isEmpty {
                ProgressView()
                    .scaleEffect(1.2)
            } else if viewModel.notifications.isEmpty {
                ContentUnavailableView("All Caught Up!", systemImage: "bell.slash", description: Text("You have no notifications."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.notifications) { notification in
                            Button {
                                Task {
                                    await viewModel.markAsRead(notification)
                                }
                            } label: {
                                NotificationCardView(notification: notification)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            if !viewModel.notifications.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await viewModel.markAllAsRead() }
                    }) {
                        Image(systemName: "checkmark.circle.badge.xmark")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.fetchNotifications()
        }
        .task {
            await viewModel.fetchNotifications()
        }
    }
}
