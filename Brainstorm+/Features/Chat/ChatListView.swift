import SwiftUI
import Combine
import Supabase

public struct ChatListView: View {
    @StateObject private var viewModel: ChatListViewModel
    
    public init(viewModel: ChatListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.channels.isEmpty {
                    ProgressView()
                } else if viewModel.channels.isEmpty {
                    ContentUnavailableView("No Messages", systemImage: "message", description: Text("You have no active chats yet."))
                } else {
                    List(viewModel.channels) { channel in
                        NavigationLink(destination: ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))) {
                            HStack(spacing: 16) {
                                // Avatar
                                ZStack {
                                    Circle()
                                        .fill(channelColor(channel.type).opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: channelIcon(channel.type))
                                        .font(.system(size: 20))
                                        .foregroundColor(channelColor(channel.type))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(channel.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(ChatDateFormatter.format(channel.lastMessageAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(channel.lastMessage ?? "No messages yet")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Team Chat")
            .zyErrorBanner($viewModel.errorMessage)
            .refreshable {
                await viewModel.fetchChannels()
            }
            .task {
                await viewModel.fetchChannels()
            }
        }
    }
    
    private func channelColor(_ type: ChatChannel.ChannelType) -> Color {
        switch type {
        case .direct: return .blue
        case .group: return .green
        case .announcement: return .orange
        }
    }
    
    private func channelIcon(_ type: ChatChannel.ChannelType) -> String {
        switch type {
        case .direct: return "person.fill"
        case .group: return "person.3.fill"
        case .announcement: return "megaphone.fill"
        }
    }
}
