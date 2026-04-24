import SwiftUI
import Combine
import Supabase

public struct ChatListView: View {
    @StateObject private var viewModel: ChatListViewModel
    @State private var showNewConversation: Bool = false

    // Phase 6.3: isEmbedded parameterization
    // 当 MessagesView（Tab 4）把 ChatListView 作为 sub-tab 内嵌进外层
    // NavigationStack 时,此处跳过自己的 NavigationStack,避免 nav bar 双层叠。
    public let isEmbedded: Bool

    public init(viewModel: ChatListViewModel, isEmbedded: Bool = false) {
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
        ZStack {
            // Fusion ambient backdrop — soft diffused glow beneath the list
            // so the channel rows float above an editorial gradient rather
            // than a flat system background.
            BsColor.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if viewModel.isLoading && viewModel.channels.isEmpty {
                        // Skeleton 行匹配 channelRow 实际高度，比 ProgressView 更少抖动
                        channelSkeleton
                    } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResultsList
                    } else if viewModel.channels.isEmpty {
                        BsEmptyState(
                            title: "还没有会话",
                            systemImage: "message",
                            description: "点击右上角的笔图标，开始一段对话"
                        )
                    } else {
                        channelList
                    }
                }
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
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptic.light()
                    showNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(BsColor.brandAzure)
                        .frame(width: 32, height: 32)
                        .glassEffect(
                            .regular.tint(BsColor.brandAzure.opacity(0.18)).interactive(),
                            in: Circle()
                        )
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

    // MARK: - Skeleton

    /// Loading skeleton —— 匹配 channelRow 高度避免首屏跳动
    @ViewBuilder
    private var channelSkeleton: some View {
        VStack(spacing: BsSpacing.md) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: BsSpacing.lg) {
                    Circle()
                        .fill(BsColor.inkFaint.opacity(0.18))
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BsColor.inkFaint.opacity(0.18))
                            .frame(height: 14)
                            .frame(maxWidth: 160, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BsColor.inkFaint.opacity(0.12))
                            .frame(height: 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, BsSpacing.lg)
                .padding(.vertical, BsSpacing.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, BsSpacing.md)
        .shimmer()
        .accessibilityLabel("正在加载会话")
    }

    // MARK: - Channel list

    @ViewBuilder
    private var channelList: some View {
        List {
            ForEach(Array(viewModel.channels.enumerated()), id: \.element.id) { index, channel in
                NavigationLink(value: channel) {
                    channelRow(channel)
                }
                .bsAppearStagger(index: index)
            }
        }
        .listStyle(.plain)
        // Fusion: kill the list's opaque backdrop so the page background shows
        // through behind each row.
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func channelRow(_ channel: ChatChannel) -> some View {
        HStack(spacing: BsSpacing.lg) {
            ZStack {
                Circle()
                    .fill(channelColor(channel.type).opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(
                        // Hairline ring for a subtle glass/linear treatment —
                        // matches the Dashboard attendance ring aesthetic.
                        Circle()
                            .stroke(channelColor(channel.type).opacity(0.25), lineWidth: 0.5)
                    )
                Image(systemName: channelIcon(channel.type))
                    .font(.system(.title3))
                    .foregroundStyle(channelColor(channel.type))
            }

            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                HStack(spacing: BsSpacing.xs) {
                    Text(channel.name)
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: BsSpacing.xs)
                    Text(ChatDateFormatter.format(channel.lastMessageAt))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .monospacedDigit()
                        .layoutPriority(1)
                }

                Text(channel.lastMessage?.isEmpty == false
                     ? channel.lastMessage!
                     : "尚无消息 · 发一条开始聊天")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(channel.lastMessage?.isEmpty == false
                                      ? BsColor.inkMuted
                                      : BsColor.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, BsSpacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsList: some View {
        if viewModel.isSearching && viewModel.searchResults.isEmpty {
            VStack(spacing: BsSpacing.sm) {
                ProgressView()
                Text("正在搜索消息…")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.searchResults.isEmpty {
            // BsEmptyState signature mismatch: iOS 原生 .search(text:) 自带本地化文案，保留
            ContentUnavailableView.search(text: viewModel.searchQuery)
        } else {
            List(viewModel.searchResults) { result in
                NavigationLink(value: result.channel) {
                    searchResultRow(result)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: ChatSearchResult) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            HStack {
                Image(systemName: channelIcon(result.channel.type))
                    .foregroundStyle(channelColor(result.channel.type))
                Text(result.channel.name)
                    .font(BsTypography.cardSubtitle)
                    .foregroundStyle(BsColor.ink)
                Spacer()
                Text(ChatDateFormatter.format(result.message.createdAt))
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            // Sprint 3.5: 把查询词在消息正文里高亮出来，用户一眼看到"为什么"
            // 这条消息命中。同一个 highlighter 也顺便渲染 @mention，列表里看到
            // 的语义跟打开会话看到的一致。
            if result.message.content.isEmpty {
                Text("[附件]")
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(2)
            } else {
                Text(ChatContentHighlighter.attributed(
                    result.message.content,
                    searchTerm: viewModel.searchQuery
                ))
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, BsSpacing.xs)
    }

    private func channelColor(_ type: ChatChannel.ChannelType) -> Color {
        switch type {
        case .direct:       return BsColor.brandAzure
        case .group:        return BsColor.success
        case .announcement: return BsColor.brandCoral
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
