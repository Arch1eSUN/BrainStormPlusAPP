import SwiftUI
import Combine
import Supabase

public struct ChatListView: View {
    @StateObject private var viewModel: ChatListViewModel
    @State private var showNewConversation: Bool = false

    public init(viewModel: ChatListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.channels.isEmpty {
                    ProgressView()
                } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsList
                } else if viewModel.channels.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "message",
                        description: Text("You have no active chats yet.")
                    )
                } else {
                    channelList
                }
            }
            // Sprint 3.4: value-based navigation. `ChatRoomViewModel` is only
            // constructed when the destination actually renders, not once per
            // list row — previous eager pattern was instantiating a Supabase
            // client + realtime subscriber for every channel in the list just
            // to prepare the nav link.
            .navigationDestination(for: ChatChannel.self) { channel in
                ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))
            }
            .navigationTitle("Team Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("新建会话")
                }
            }
            .sheet(isPresented: $showNewConversation) {
                NewConversationSheet(viewModel: viewModel) { _ in
                    // Channel already inserted at top by the sheet; no extra
                    // nav needed — the user sees the new row and taps to
                    // enter.
                }
            }
            .zyErrorBanner($viewModel.errorMessage)
            // `.searchable` binds to a Published on the VM so the search UI
            // survives background re-renders of the navigation stack without
            // losing the query.
            .searchable(text: $viewModel.searchQuery, prompt: "搜索消息…")
            .onChange(of: viewModel.searchQuery) { _, newValue in
                // Minimal debounce: 250ms of idle before firing. Not using
                // `.task(id:)` on the view because `searchQuery` mutations
                // would otherwise cancel mid-typed edits; a raw Task with a
                // sleep + `Task.isCancelled` check is lighter and mirrors
                // AsyncStream.debounce.
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    guard viewModel.searchQuery == newValue else { return }
                    await viewModel.searchMessages(query: newValue)
                }
            }
            .refreshable {
                await viewModel.fetchChannels()
            }
            .task {
                await viewModel.fetchChannels()
            }
        }
    }

    // MARK: - Channel list

    @ViewBuilder
    private var channelList: some View {
        List(viewModel.channels) { channel in
            NavigationLink(value: channel) {
                channelRow(channel)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func channelRow(_ channel: ChatChannel) -> some View {
        HStack(spacing: 16) {
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

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsList: some View {
        if viewModel.isSearching && viewModel.searchResults.isEmpty {
            ProgressView()
        } else if viewModel.searchResults.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchQuery)
        } else {
            List(viewModel.searchResults) { result in
                NavigationLink(value: result.channel) {
                    searchResultRow(result)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: ChatSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: channelIcon(result.channel.type))
                    .foregroundColor(channelColor(result.channel.type))
                Text(result.channel.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Spacer()
                Text(ChatDateFormatter.format(result.message.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            // Sprint 3.5: 把查询词在消息正文里高亮出来，用户一眼看到"为什么"
            // 这条消息命中。同一个 highlighter 也顺便渲染 @mention，列表里看到
            // 的语义跟打开会话看到的一致。
            if result.message.content.isEmpty {
                Text("[附件]")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text(ChatContentHighlighter.attributed(
                    result.message.content,
                    searchTerm: viewModel.searchQuery
                ))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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
