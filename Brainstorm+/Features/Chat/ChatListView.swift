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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // MessagesView 包裹本 view 时（isEmbedded=true）外层已有 NavStack +
        // segmented picker + 自己的 navigationTitle。再在 child 里 set 一次
        // navigationTitle("消息") 会被 MessagesView 的覆盖,但 toolbar / search
        // 仍然指向外层 stack,不冲突。
        // Sprint 3.4: value-based navigation. `ChatRoomViewModel` is only
        // constructed when the destination actually renders, not once per
        // list row — previous eager pattern was instantiating a Supabase
        // client + realtime subscriber for every channel in the list just
        // to prepare the nav link.
        .navigationDestination(for: ChatChannel.self) { channel in
            // Iter 7 Fix 1 — DM channel: pass peer Profile so room title can
            // show the other user's full name instead of the stored channel
            // name (which is often "Direct Message" for legacy DMs).
            ChatRoomView(
                viewModel: ChatRoomViewModel(client: supabase, channel: channel),
                titleOverride: viewModel.directPeers[channel.id].map { MentionPickerSheet.displayLabel(for: $0) }
            )
        }
        // 只在非 embedded 时才挂 nav title —— MessagesView 外层已经设置了
        // "消息"的 large title,若 child 在同一条 NavStack 上 又 `.navigationTitle`
        // 一次 SwiftUI 会在 child appear 的一瞬把外层 title 替换成 child 的值
        // （iOS 26 Liquid Glass 下这个替换有可见闪烁 / nav bar collapse）。
        .modifier(ConditionalNavTitle(isEmbedded: isEmbedded, title: "消息", display: .large))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
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
            // Minimal debounce: 250ms of idle before firing. Iter 7 Phase 1.2:
            // routes through FTS RPC (chat_search_messages) for proper full-text
            // matching with RLS;旧 ILIKE 代码作为 fallback 留在 VM 里。
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                guard viewModel.searchQuery == newValue else { return }
                await viewModel.searchMessagesFTS(query: newValue)
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: BsSpacing.lg, bottom: 4, trailing: BsSpacing.lg))
                .buttonStyle(.plain)
                .contextMenu { channelContextMenu(channel) }
            }
        }
        .listStyle(.plain)
        // Fusion: kill the list's opaque backdrop so the page background shows
        // through behind each row.
        .scrollContentBackground(.hidden)
    }

    /// Iter 7 Phase 1.2 — long-press on channel row.
    @ViewBuilder
    private func channelContextMenu(_ channel: ChatChannel) -> some View {
        let isPinned = (viewModel.memberships[channel.id]?.pinnedAt) != nil
        let isMuted = viewModel.memberships[channel.id]?.isCurrentlyMuted == true

        Button {
            Task { await viewModel.setPinned(channelId: channel.id, pinned: !isPinned) }
        } label: {
            Label(isPinned ? "取消置顶" : "置顶频道",
                  systemImage: isPinned ? "pin.slash" : "pin.fill")
        }

        if isMuted {
            Button {
                Task { await viewModel.setMuted(channelId: channel.id, until: nil) }
            } label: {
                Label("取消静音", systemImage: "bell")
            }
        } else {
            Menu {
                ForEach(MutePreset.allCases) { preset in
                    Button(preset.label) {
                        Task {
                            await viewModel.setMuted(
                                channelId: channel.id,
                                until: preset.resolve()
                            )
                        }
                    }
                }
            } label: {
                Label("静音", systemImage: "bell.slash")
            }
        }
    }

    /// Bug-fix(视图割裂): channel row 之前是裸 HStack + system list 默认背景,
    /// 跟 Approvals/Tasks 等模块的 BsContentCard row 视觉断层。包一层
    /// BsContentCard,token 跟全 app 同步。
    ///
    /// Iter 7 Fix 1 — DM 频道用对方 Profile 的中文姓名 + 头像渲染,而不是
    /// chat_channels.name 那个通用占位。Group / announcement 频道照旧。
    @ViewBuilder
    private func channelRow(_ channel: ChatChannel) -> some View {
        let peer: Profile? = (channel.type == .direct) ? viewModel.directPeers[channel.id] : nil
        let isPinned = (viewModel.memberships[channel.id]?.pinnedAt) != nil
        let isMuted = viewModel.memberships[channel.id]?.isCurrentlyMuted == true
        let displayName: String = {
            if let peer = peer {
                return MentionPickerSheet.displayLabel(for: peer)
            }
            return channel.name
        }()

        BsContentCard(padding: .none) {
            HStack(spacing: BsSpacing.lg) {
                rowAvatar(channel: channel, peer: peer)

                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    HStack(spacing: BsSpacing.xs) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BsColor.brandAzure)
                                .accessibilityLabel("已置顶")
                        }
                        Text(displayName)
                            .font(BsTypography.cardTitle)
                            .foregroundStyle(BsColor.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BsColor.inkFaint)
                                .accessibilityLabel("已静音")
                        }
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
            .padding(.horizontal, BsSpacing.md)
            .padding(.vertical, BsSpacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isMuted ? 0.7 : 1.0)
            .background(
                isPinned
                ? RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.04))
                : nil
            )
        }
        .contentShape(Rectangle())
    }

    /// Iter 7 Fix 1 — DM 频道画对方头像;否则保留按 channel type 着色的图标圈。
    @ViewBuilder
    private func rowAvatar(channel: ChatChannel, peer: Profile?) -> some View {
        if let peer = peer, let urlStr = peer.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    avatarInitial(for: peer)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().stroke(BsColor.borderSubtle, lineWidth: 0.5))
        } else if let peer = peer {
            avatarInitial(for: peer)
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(BsColor.borderSubtle, lineWidth: 0.5))
        } else {
            ZStack {
                Circle()
                    .fill(channelColor(channel.type).opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(channelColor(channel.type).opacity(0.25), lineWidth: 0.5)
                    )
                Image(systemName: channelIcon(channel.type))
                    .font(.system(.title3))
                    .foregroundStyle(channelColor(channel.type))
            }
        }
    }

    @ViewBuilder
    private func avatarInitial(for p: Profile) -> some View {
        let initial = MentionPickerSheet.displayLabel(for: p).prefix(1)
        ZStack {
            BsColor.brandAzure.opacity(0.18)
            Text(String(initial).uppercased())
                .font(BsTypography.cardSubtitle)
                .foregroundStyle(BsColor.brandAzureDark)
        }
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
        let peer: Profile? = (result.channel.type == .direct)
            ? viewModel.directPeers[result.channel.id]
            : nil
        let displayName: String = peer.map { MentionPickerSheet.displayLabel(for: $0) }
            ?? result.channel.name
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            HStack {
                Image(systemName: channelIcon(result.channel.type))
                    .foregroundStyle(channelColor(result.channel.type))
                Text(displayName)
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

// MARK: - ConditionalNavTitle
// 只在 !isEmbedded 时应用 `.navigationTitle`/`.navigationBarTitleDisplayMode`,
// embedded 场景下完全不挂 title modifier —— 让外层容器（MessagesView）
// 独占导航栏标题控制。
private struct ConditionalNavTitle: ViewModifier {
    let isEmbedded: Bool
    let title: String
    let display: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(display)
        }
    }
}
