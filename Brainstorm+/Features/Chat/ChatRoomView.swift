import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers

public struct ChatRoomView: View {
    @StateObject private var viewModel: ChatRoomViewModel
    /// Iter 7 Fix 1 — when entering a DM, ChatList resolves peer Profile and
    /// passes their display label here so the navigation title reads "张三"
    /// instead of the stored channel.name (often a generic placeholder).
    public let titleOverride: String?

    // MARK: - Sprint 3.3 附件选择状态
    //
    // `pendingUploads` 是"已选但未发送"的附件缓冲区——用户可以连续挑多张图 /
    // 多个文件再一并发出。`photoItems` 是 PhotosPicker 的 selection 绑定；
    // `onChange` 里把它转成 `PendingUpload` 再清掉，避免 picker 重复触发。
    @State private var pendingUploads: [PendingUpload] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    // MARK: - Sprint 3.4 回复状态
    //
    // 被回复的原消息 —— 用户从 contextMenu 选 "回复" 后塞进来，输入栏上方会
    // 出现一个预览条，发送时把 id 作为 reply_to 写入 chat_messages。
    @State private var replyingTo: ChatMessage? = nil

    // MARK: - Phase 1.1: Slack-grade state

    /// Per-device 草稿持久化(配 RPC 跨设备兜底)。AppStorage key 含 channel id。
    @State private var localDraft: String = ""

    /// @ 提及 sheet 触发标记 + 当前 query 片段。
    @State private var showMentionPicker: Bool = false
    @State private var mentionQuery: String = ""

    /// Thread sheet —— 用户点击消息底部 "n 条回复 →" 进入。
    @State private var threadParent: ChatMessage? = nil

    /// 系统当前 channel id 字符串(用于 AppStorage key)。
    private var draftKey: String { "chat.draft.\(viewModel.channel.id.uuidString)" }

    /// Iter 8 polish — viewport tracker for chat_mark_read. Replaces the old
    /// `.onAppear + Task.sleep(0.5s)` per-bubble pattern that fired marks
    /// even when a bubble only briefly flashed past during fast scrolls.
    /// 1.5s dwell threshold; entries dropped on `.onDisappear`.
    @StateObject private var visibilityTracker: ChatVisibilityTracker

    /// Iter 8 polish — which message's "(已编辑)" footer is currently showing
    /// the edit-timestamp popover. Tap to toggle; nil hides.
    @State private var editedFootnotePopoverId: UUID? = nil

    public init(viewModel: ChatRoomViewModel, titleOverride: String? = nil) {
        let vm = viewModel
        _viewModel = StateObject(wrappedValue: vm)
        _visibilityTracker = StateObject(wrappedValue: ChatVisibilityTracker(
            dwellThreshold: 1.5,
            onMarkRead: { [weak vm] id in
                guard let vm = vm else { return }
                await vm.markMessageRead(id)
            }
        ))
        self.titleOverride = titleOverride
    }

    public var body: some View {
        ZStack {
            // 纯净 pageBackground —— 气泡 glass tint 漂在上方。
            BsColor.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                content

                if !viewModel.accessDenied {
                    // Iter 7 Phase 1.2 — typing indicator (user-facing names).
                    let activeTypers = viewModel.typingUsers.values
                        .sorted { $0.lastSeen > $1.lastSeen }
                    if !activeTypers.isEmpty {
                        TypingIndicator(users: Array(activeTypers))
                            .animation(BsMotion.Anim.smooth, value: activeTypers.count)
                    }
                    if let parent = replyingTo {
                        replyPreviewStrip(parent: parent)
                    }
                    if !pendingUploads.isEmpty {
                        pendingAttachmentsStrip
                    }
                    MessageInputBar(
                        text: $viewModel.draft,
                        isSending: viewModel.isSending,
                        canSend: canSend,
                        placeholder: "输入消息…",
                        onSend: sendTapped,
                        onAttachmentTap: { showFileImporter = true },
                        onPhotoTap: { /* presented inline below as PhotosPicker overlay */ },
                        onEmojiTap: { /* Phase 1.2: emoji picker */ },
                        onMentionTap: {
                            mentionQuery = ""
                            showMentionPicker = true
                        }
                    )
                    .background(
                        // PhotosPicker 不能直接当 button —— 用一个透明 overlay 让
                        // "图片"按钮的 hit-area 触发原生 PhotosPicker sheet。
                        photosPickerHidden
                    )
                }
            }
        }
        .navigationTitle(titleOverride ?? viewModel.channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .task {
            // 先把 per-device AppStorage 读到 VM,RPC 再兜底跨设备。
            let stored = UserDefaults.standard.string(forKey: draftKey) ?? ""
            if viewModel.draft.isEmpty && !stored.isEmpty {
                viewModel.draft = stored
            }
            await viewModel.bootstrap()
        }
        .onDisappear {
            viewModel.teardown()
            visibilityTracker.reset()
        }
        .onChange(of: viewModel.draft) { _, newValue in
            // 1) 即时写入 per-device AppStorage(无延迟,免丢)
            UserDefaults.standard.set(newValue, forKey: draftKey)
            // 2) 500ms debounce 写入 RPC(跨设备)
            viewModel.saveDraftDebounced(newValue)
            // 3) 检测 @ 触发 —— 末位字符是 @ 且前一个字符不是字母数字时弹 sheet
            detectMentionTrigger(in: newValue)
            // 4) Iter 7 Phase 1.2 — 用户在输入 → broadcast typing presence
            //    (内部 800ms rate limit, 不会狂打)
            if !newValue.isEmpty {
                viewModel.notifyTyping()
            }
        }
        // PhotosPicker 把选中的 PhotosPickerItem 塞进 $photoItems，
        // 这里监听变化 → loadTransferable(Data) → 追加到 pendingUploads。
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await ingestPhotoItems(newItems) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerSheet(
                candidates: viewModel.mentionCandidates,
                query: $mentionQuery,
                onPick: { profile in
                    insertMention(profile)
                    showMentionPicker = false
                },
                onDismiss: { showMentionPicker = false }
            )
        }
        .sheet(item: $threadParent) { parent in
            ChatThreadView(
                client: supabase,
                channel: viewModel.channel,
                parent: parent,
                currentUserId: viewModel.currentUserId
            )
            .bsSheetStyle(.detail)
        }
    }

    /// Slack-grade Send 闸门:无文本且无附件时禁用。
    private var canSend: Bool {
        if viewModel.isSending { return false }
        let empty = viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !(empty && pendingUploads.isEmpty)
    }

    /// 隐藏 PhotosPicker —— 跟 "图片" 按钮 hit-area 重叠,系统弹出原生 sheet。
    @ViewBuilder
    private var photosPickerHidden: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: 9,
            matching: .images
        ) { Color.clear }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    /// 检测末位字符是 @,且 @ 之前是 word boundary(空格 / 字符串开头)
    /// → 弹 mention sheet。query 取 @ 之后到末尾的子串。
    private func detectMentionTrigger(in text: String) {
        guard !text.isEmpty else {
            if showMentionPicker { showMentionPicker = false }
            return
        }
        // 找到光标位置之前最近一个 @ —— 简化策略:取整串最后一个 @,看它后面
        // 有没有空格;没空格 → 在 mention 中,query = @ 之后部分。
        guard let atRange = text.range(of: "@", options: .backwards) else {
            if showMentionPicker { showMentionPicker = false }
            return
        }
        let after = String(text[atRange.upperBound...])
        if after.contains(" ") || after.contains("\n") {
            // @ 后已经空格/换行,说明用户已结束这次 mention
            if showMentionPicker { showMentionPicker = false }
            return
        }
        // 检查 @ 前一字符是不是 word boundary
        if atRange.lowerBound > text.startIndex {
            let prevIdx = text.index(before: atRange.lowerBound)
            let prevChar = text[prevIdx]
            if prevChar.isLetter || prevChar.isNumber {
                // 像 "abc@def" —— 不视作 mention 触发(可能是邮箱)
                if showMentionPicker { showMentionPicker = false }
                return
            }
        }
        mentionQuery = after
        if !showMentionPicker {
            showMentionPicker = true
        }
    }

    /// 把当前文本里最后一个 @xxx 片段替换成 `@DisplayName ` (含末尾空格)。
    /// Iter 7 Fix 2 — 优先中文姓名(`fullName`),让插入文本读起来跟 mention sheet
    /// 看到的一致(@张三 而不是 @zhangsan)。
    private func insertMention(_ profile: Profile) {
        let text = viewModel.draft
        guard let atRange = text.range(of: "@", options: .backwards) else { return }
        let displayName = MentionPickerSheet.displayLabel(for: profile)
        let replacement = "@\(displayName) "
        viewModel.draft = String(text[..<atRange.lowerBound]) + replacement
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.accessDenied {
            Spacer()
            Text("你没有权限查看此频道")
                .font(BsTypography.body)
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(BsSpacing.lg)
            Spacer()
        } else if viewModel.isLoading && viewModel.messages.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: BsSpacing.md) {
                            // Iter 7 Phase 1.2 — top sentinel for infinite scroll up.
                            // .onAppear → load older page; loader visible when fetching.
                            if viewModel.hasMoreOlder {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await viewModel.loadMoreOlderMessages() }
                                    }
                            }
                            if viewModel.isLoadingOlder {
                                HStack(spacing: BsSpacing.xs) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("加载更多…")
                                        .font(BsTypography.captionSmall)
                                        .foregroundStyle(BsColor.inkMuted)
                                }
                                .padding(.vertical, BsSpacing.sm)
                                .frame(maxWidth: .infinity)
                            }
                            ForEach(viewModel.messages) { msg in
                                // Phase 1.1: 在第一条 created_at > unreadAnchor 的
                                // 消息上方插入 UnreadDividerView。
                                if shouldShowUnreadDivider(before: msg) {
                                    UnreadDividerView(unreadCount: unreadCountFromAnchor)
                                        .id("unread-divider")
                                }
                                messageBubble(
                                    msg: msg,
                                    isCurrentUser: msg.senderId == viewModel.currentUserId
                                )
                                .id(msg.id)
                            }

                            // Bottom anchor —— 用 onAppear/onDisappear 推 isAtBottom
                            Color.clear
                                .frame(height: 1)
                                .id("bottom-anchor")
                                .onAppear {
                                    viewModel.isAtBottom = true
                                    if viewModel.pendingBelowCount > 0 {
                                        viewModel.pendingBelowCount = 0
                                    }
                                    viewModel.markReadDebounced()
                                }
                                .onDisappear {
                                    viewModel.isAtBottom = false
                                }
                        }
                        .padding(.horizontal, BsSpacing.lg)
                        .padding(.vertical, BsSpacing.md)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        // Phase 1.1: 仅当用户在底部时才自动滚;离开底部时让 pill 接力。
                        if viewModel.isAtBottom {
                            withAnimation(BsMotion.Anim.smooth) {
                                proxy.scrollTo("bottom-anchor", anchor: .bottom)
                            }
                        }
                    }
                    .task {
                        // 首次进入:滚到底部(若有未读分隔线 → 滚到分隔线)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if let _ = viewModel.unreadAnchor,
                           viewModel.messages.contains(where: { ($0.createdAt ?? .distantPast) > (viewModel.unreadAnchor ?? .distantFuture) }) {
                            withAnimation { proxy.scrollTo("unread-divider", anchor: .top) }
                        } else {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }

                    // Phase 1.1: "新消息 ↓" floating pill —— 仅当 isAtBottom == false
                    // 且 pendingBelowCount > 0 时显示。点击后滚到底。
                    if !viewModel.isAtBottom && viewModel.pendingBelowCount > 0 {
                        newMessagePill(proxy: proxy)
                            .padding(.bottom, BsSpacing.md)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(BsMotion.Anim.smooth, value: viewModel.pendingBelowCount)
            }
        }
    }

    // MARK: - Phase 1.1 — Unread divider helpers

    private func shouldShowUnreadDivider(before msg: ChatMessage) -> Bool {
        guard let anchor = viewModel.unreadAnchor else { return false }
        guard let created = msg.createdAt, created > anchor else { return false }
        // 只在第一条满足条件的消息上方画一次
        let firstUnread = viewModel.messages.first {
            ($0.createdAt ?? .distantPast) > anchor
        }
        return firstUnread?.id == msg.id && msg.senderId != viewModel.currentUserId
    }

    private var unreadCountFromAnchor: Int {
        guard let anchor = viewModel.unreadAnchor else { return 0 }
        return viewModel.messages.filter {
            ($0.createdAt ?? .distantPast) > anchor && $0.senderId != viewModel.currentUserId
        }.count
    }

    @ViewBuilder
    private func newMessagePill(proxy: ScrollViewProxy) -> some View {
        Button {
            Haptic.light()
            viewModel.pendingBelowCount = 0
            withAnimation(BsMotion.Anim.smooth) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } label: {
            HStack(spacing: BsSpacing.xs) {
                Text("新消息")
                Text("\(viewModel.pendingBelowCount)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(BsColor.brandCoral))
                    .foregroundStyle(.white)
                    .font(BsTypography.captionSmall)
                Image(systemName: "arrow.down")
            }
            .font(BsTypography.captionSmall)
            .foregroundStyle(BsColor.ink)
            .padding(.horizontal, BsSpacing.md)
            .padding(.vertical, BsSpacing.sm)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay(Capsule().stroke(BsColor.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pending attachments 预览条

    private var pendingAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BsSpacing.sm) {
                ForEach(pendingUploads) { upload in
                    ZStack(alignment: .topTrailing) {
                        pendingThumbnail(for: upload)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                            )

                        Button {
                            pendingUploads.removeAll { $0.id == upload.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .shadow(radius: 1)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.sm)
        }
        // Liquid Glass 也应用于附件预览条 —— 跟 composer 贴合做整体悬浮感
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
        )
    }

    @ViewBuilder
    private func pendingThumbnail(for upload: PendingUpload) -> some View {
        if let image = upload.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                BsColor.surfaceTertiary
                VStack(spacing: 2) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(BsColor.inkMuted)
                    Text(upload.fileName)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, BsSpacing.xs)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
    }

    // MARK: - Send flow

    private func sendTapped() {
        let text = viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let uploads = pendingUploads
        let replyToId = replyingTo?.id
        guard !text.isEmpty || !uploads.isEmpty else { return }

        // 乐观清 UI —— 如果上传/发送失败，errorMessage 会弹出 banner。
        viewModel.draft = ""
        UserDefaults.standard.removeObject(forKey: draftKey)
        pendingUploads = []
        replyingTo = nil

        Task {
            var attached: [ChatAttachment] = []
            for upload in uploads {
                do {
                    let att = try await viewModel.uploadAttachment(
                        data: upload.data,
                        fileName: upload.fileName,
                        mimeType: upload.mimeType
                    )
                    attached.append(att)
                } catch {
                    viewModel.errorMessage = "上传失败: \(ErrorLocalizer.localize(error))"
                    return
                }
            }
            await viewModel.sendMessage(text, attachments: attached, replyTo: replyToId)
            // 清服务端草稿(跨设备一并失效)
            await viewModel.clearDraftRemote()
        }
    }

    // MARK: - Attachment ingestion

    @MainActor
    private func ingestPhotoItems(_ items: [PhotosPickerItem]) async {
        // PhotosPickerItem 没有直接暴露 fileName —— 用 UUID + jpg 作为展示名。
        // `loadTransferable(type: Data.self)` 是 Apple 推荐姿势，会自动处理
        // iCloud / HEIC 解码（HEIC 选择时系统会降级编码为 JPEG 返回）。
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let fileName = "IMG_\(UUID().uuidString.prefix(8)).jpg"
            let preview = UIImage(data: data)
            pendingUploads.append(PendingUpload(
                data: data,
                fileName: fileName,
                mimeType: "image/jpeg",
                previewImage: preview
            ))
        }
        photoItems = []  // 清 selection，避免同一张图重复 ingest
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            if case let .failure(error) = result {
                viewModel.errorMessage = "选择文件失败: \(ErrorLocalizer.localize(error))"
            }
            return
        }
        for url in urls {
            // .fileImporter 返回的 URL 带 security scope —— 必须
            // startAccessingSecurityScopedResource 才能 Data(contentsOf:)。
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else { continue }
            let fileName = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?
                .preferredMIMEType ?? "application/octet-stream"
            let preview = mime.hasPrefix("image/") ? UIImage(data: data) : nil
            pendingUploads.append(PendingUpload(
                data: data,
                fileName: fileName,
                mimeType: mime,
                previewImage: preview
            ))
        }
    }

    /// Iter 8 polish — popover timestamp formatter for "(已编辑)" tap. Uses
    /// the same locale convention as ChatDateFormatter but always shows the
    /// full date+time (popover is the disclosure surface, no need to elide).
    private func editedTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.setLocalizedDateFormatFromTemplate("yMMMdHHmm")
        return f.string(from: date)
    }

    // MARK: - Message bubble

    @ViewBuilder
    private func messageBubble(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 50) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: BsSpacing.xs) {
                // Sprint 3.4: 如果这是一条回复消息，先画一条 "reply-to" 块。
                // 原消息可能已被撤回（isWithdrawn）或查不到（从 replyLookup 缺席），
                // 两种情况都要降级成占位文本，跟 Web 保持一致。
                if let parentId = msg.replyTo {
                    replyBlock(parentId: parentId, isCurrentUser: isCurrentUser)
                }

                if msg.isWithdrawn {
                    // Web `MessageItem` (page.tsx 渲染逻辑) —— 撤回后只留占位。
                    Text("此消息已撤回")
                        .font(BsTypography.body.italic())
                        .foregroundStyle(BsColor.inkMuted)
                        .padding(.horizontal, BsSpacing.lg)
                        .padding(.vertical, BsSpacing.sm + 2)
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: BsRadius.xl - 2, style: .continuous)
                        )
                } else if viewModel.editingMessageId == msg.id {
                    // Iter 7 Phase 1.2 — inline edit mode: 替换 bubble 为 TextField + 保存/取消。
                    inlineEditBubble(msg: msg, isCurrentUser: isCurrentUser)
                } else {
                    // 文本部分:空字符串 + 纯附件时跳过气泡,避免多一个空框。
                    if !msg.content.isEmpty {
                        Text(ChatContentHighlighter.attributed(
                            msg.content,
                            mentionColor: isCurrentUser ? BsColor.brandCoral : BsColor.brandAzure
                        ))
                            .font(BsTypography.body)
                            .padding(.horizontal, BsSpacing.lg)
                            .padding(.vertical, BsSpacing.sm + 2)
                            .glassEffect(
                                isCurrentUser
                                    ? .regular.tint(BsColor.brandAzure.opacity(0.18)).interactive()
                                    : .regular.interactive(),
                                in: bubbleShape(isCurrentUser: isCurrentUser)
                            )
                            .foregroundStyle(BsColor.ink)
                    }

                    ForEach(msg.attachments, id: \.url) { att in
                        attachmentView(att)
                    }

                    // Iter 7 Phase 1.2 — link preview card (first http(s) URL only,
                    // 减少视觉噪音)。
                    if let firstURL = msg.content.firstDetectedURL() {
                        LinkPreviewCard(
                            url: firstURL,
                            fetcher: linkPreviewFetcher(for: firstURL)
                        )
                    }

                    // Phase 4.5: reaction 芯片条
                    if !msg.reactions.isEmpty {
                        reactionChipRow(msg: msg, isCurrentUser: isCurrentUser)
                    }

                    // Phase 1.1: 线程入口
                    if msg.replyTo == nil && msg.threadReplyCount > 0 {
                        threadFooter(msg: msg)
                    }

                    // Iter 7 Phase 1.2 — read receipt avatars (own messages only,
                    // shown bottom-right of bubble).
                    if isCurrentUser && !msg.readBy.isEmpty {
                        readReceiptStack(readers: msg.readBy)
                    }
                }

                // 时间 + (已编辑) marker
                HStack(spacing: BsSpacing.xs) {
                    let timeText = ChatDateFormatter.format(msg.createdAt)
                    if !timeText.isEmpty {
                        Text(timeText)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    if let editedAt = msg.editedAt {
                        // Iter 8 polish — smaller / lighter footer + tappable
                        // popover with the exact edit timestamp. Animated
                        // .opacity + .scale on first appear so the marker
                        // doesn't pop in jarringly.
                        Button {
                            // Toggle popover for this bubble
                            editedFootnotePopoverId = (editedFootnotePopoverId == msg.id) ? nil : msg.id
                        } label: {
                            Text("(已编辑)")
                                .font(BsTypography.captionSmall)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .popover(isPresented: Binding(
                            get: { editedFootnotePopoverId == msg.id },
                            set: { if !$0 { editedFootnotePopoverId = nil } }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("于 \(editedTimestamp(editedAt)) 编辑")
                                    .font(BsTypography.captionSmall)
                                    .foregroundStyle(BsColor.ink)
                            }
                            .padding(.horizontal, BsSpacing.md)
                            .padding(.vertical, BsSpacing.sm)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
            .onAppear {
                // Iter 8 polish — register with the visibility tracker. The
                // tracker fires markMessageRead only after a 1.5s dwell, so
                // momentum scrolls past a bubble no longer count as "read".
                // Skipping own messages and already-read ones is enforced by
                // the VM (idempotent), but the tracker also avoids
                // re-firing within the same room session.
                visibilityTracker.register(msg.id)
            }
            .onDisappear {
                // Drops the dwell timer if the user scrolled the bubble out
                // before the threshold elapsed.
                visibilityTracker.unregister(msg.id)
            }
            // contextMenu —— 长按系统 v3 (docs/longpress-system.md)
            //
            // iOS 26 `.contextMenu(menuItems:preview:)`:
            //   • preview: 放大版气泡 —— 系统自动做 zoom-in 弹动画
            //   • menuItems: 顶部横向 emoji reaction picker(参考 Slack iOS / iMessage)
            //                + Divider + 标准动作列表
            //
            // 横向 reaction picker 取代旧 v2 的 "添加表情" Menu submenu ——
            // 一次手势 + 一次点击就能投表情,体感跟 iMessage `tapback` 一致。
            //
            // 撤回 = 数据库 mutation(chat_withdraw_message RPC,2 分钟窗口)
            // 一并替代了 "删除" —— chat_messages 没有 hard-delete 路径,
            // 删除统一走撤回(Web 行为亦同)。
            //
            // 转发 = 暂以 "拷贝带 attribution 的引用块" 形式实现。
            // 完整 channel-picker 转发待新 sprint。
            .contextMenu(
                menuItems: {
                    if !msg.isWithdrawn {
                        // —— 顶部:横向 emoji reaction picker(Slack iOS pattern)
                        // SwiftUI 不支持把任意 View 塞进 contextMenu menuItems,
                        // 但 iOS 26 允许 controls (Picker / 小按钮组)。我们
                        // 把 6 个常用 emoji 摊成 6 个独立按钮 + 1 个 "更多" Menu;
                        // 系统 16pt 图标 + 紧密布局让它视觉上接近 Slack 的横向条。
                        ControlGroup {
                            ForEach(Self.quickEmojis, id: \.self) { emoji in
                                Button {
                                    Task { await viewModel.toggleReaction(messageId: msg.id, emoji: emoji) }
                                } label: {
                                    Text(emoji)
                                }
                            }
                            Menu {
                                ForEach(Self.extendedEmojis, id: \.self) { emoji in
                                    Button {
                                        Task { await viewModel.toggleReaction(messageId: msg.id, emoji: emoji) }
                                    } label: {
                                        Text(emoji)
                                    }
                                }
                            } label: {
                                Label("更多", systemImage: "plus")
                            }
                        }
                        .controlGroupStyle(.compactMenu)

                        Divider()

                        // —— 中部:mutation 优先
                        Button {
                            replyingTo = msg
                        } label: {
                            Label("回复", systemImage: "arrowshape.turn.up.left")
                        }

                        // Phase 1.1: 线程回复入口 —— 顶层消息才能开线程。
                        if msg.replyTo == nil {
                            Button {
                                threadParent = msg
                            } label: {
                                Label("在线程中回复", systemImage: "bubble.left.and.bubble.right")
                            }
                        }

                        if !msg.content.isEmpty {
                            Button {
                                UIPasteboard.general.string = msg.content
                                Haptic.light()
                            } label: {
                                Label("复制文本", systemImage: "doc.on.doc")
                            }
                        }

                        // Iter 7 Phase 1.2 — 编辑 (own + 5min window)
                        if viewModel.canEdit(msg) {
                            Button {
                                viewModel.beginEditing(msg.id)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }

                        // 仅别人的消息显示 @提及 / 转发
                        if !isCurrentUser {
                            Button {
                                replyingTo = msg
                                if !viewModel.draft.hasPrefix("@") {
                                    viewModel.draft = "@" + viewModel.draft
                                }
                            } label: {
                                Label("@提及此人", systemImage: "at")
                            }

                            Button {
                                let stamp = ChatDateFormatter.format(msg.createdAt)
                                let body = msg.content.isEmpty ? "[非文本消息]" : msg.content
                                UIPasteboard.general.string = "「转发\(stamp.isEmpty ? "" : " · " + stamp)」\n\(body)"
                                Haptic.success()
                            } label: {
                                Label("转发(复制引用)", systemImage: "arrowshape.turn.up.right")
                            }
                        }

                        // —— 底部:destructive
                        if isCurrentUser && canWithdraw(msg) {
                            Divider()
                            Button(role: .destructive) {
                                Haptic.warning()
                                Task { await viewModel.withdrawMessage(msg.id) }
                            } label: {
                                Label("撤回", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                },
                preview: {
                    // iOS 26 zoom-in preview —— 同一气泡 body,放在白色背景里
                    // 让系统的"放大动画 + 半透明遮罩"自然生效。这里不能用
                    // Spacer/Container 占满全屏,否则 preview 会撑到屏幕边。
                    enlargedPreview(msg: msg, isCurrentUser: isCurrentUser)
                        .padding(BsSpacing.lg)
                        .frame(maxWidth: 320)
                }
            )

            if !isCurrentUser { Spacer(minLength: 50) }
        }
    }

    /// 2 分钟窗口，跟 Web `page.tsx:386-390` + RPC 保持一致。
    /// `createdAt` 是 Optional —— 若 nil（理论上不会，但模型允许）我们保守
    /// 返回 false，避免让用户点开一个注定会被 RPC 拒绝的入口。
    private func canWithdraw(_ msg: ChatMessage) -> Bool {
        guard let created = msg.createdAt else { return false }
        return Date().timeIntervalSince(created) < 120
    }

    /// Fusion 气泡形状 —— iMessage 风格非对称圆角。
    /// 自己一侧（right-anchor）收右下尖角 4pt；对方一侧（left-anchor）
    /// 收左下尖角 4pt。其他三角 16pt 圆角。
    private func bubbleShape(isCurrentUser: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: isCurrentUser ? 16 : 4,
            bottomTrailingRadius: isCurrentUser ? 4 : 16,
            topTrailingRadius: 16,
            style: .continuous
        )
    }

    /// Sprint 3.4: 回复块。引用原消息一行预览 —— 被撤回 / 找不到 时降级。
    @ViewBuilder
    private func replyBlock(parentId: UUID, isCurrentUser: Bool) -> some View {
        let parent = viewModel.replyLookup[parentId]
        let preview: String = {
            guard let p = parent else { return "原消息不可用" }
            if p.isWithdrawn { return "消息已撤回" }
            if !p.content.isEmpty { return p.content }
            if !p.attachments.isEmpty {
                return p.attachments.allSatisfy({ $0.isImage }) ? "[图片]" : "[文件]"
            }
            return "[消息]"
        }()

        HStack(spacing: 6) {
            Rectangle()
                .frame(width: 2)
                .foregroundStyle(BsColor.inkFaint)
            Text(preview)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, BsSpacing.sm + 2)
        .padding(.vertical, BsSpacing.xs + 2)
        .background(BsColor.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous))
    }

    /// Phase 1.1 — 线程 footer。显示在带有 thread_reply_count > 0 的顶层
    /// 消息底部,点击进入 ChatThreadView sheet。
    @ViewBuilder
    private func threadFooter(msg: ChatMessage) -> some View {
        Button {
            Haptic.light()
            threadParent = msg
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(msg.threadReplyCount) 条回复")
                    .font(BsTypography.captionSmall)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(BsColor.brandAzureDark)
            .padding(.horizontal, BsSpacing.sm + 2)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(BsColor.brandAzure.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(BsColor.brandAzure.opacity(0.20), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reply preview strip (above input bar) — Liquid Glass

    private func replyPreviewStrip(parent: ChatMessage) -> some View {
        let preview: String = {
            if parent.isWithdrawn { return "消息已撤回" }
            if !parent.content.isEmpty { return parent.content }
            if !parent.attachments.isEmpty {
                return parent.attachments.allSatisfy({ $0.isImage }) ? "[图片]" : "[文件]"
            }
            return "[消息]"
        }()
        return HStack(spacing: BsSpacing.sm) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.brandAzure)
            Text("回复: \(preview)")
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(.horizontal, BsSpacing.md + 2)
        .padding(.vertical, BsSpacing.sm)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(BsColor.borderSubtle),
            alignment: .top
        )
    }

    // Phase 4.5: 与 Web `QUICK_EMOJIS` (page.tsx:70) 对齐。
    // Long-press v3:横向 reaction picker 直接展示这 6 个,触达成本最低。
    private static let quickEmojis: [String] = ["👍", "❤️", "😂", "😮", "🎉", "🔥"]

    // Long-press v3:"+ 更多" submenu —— 给少见但常用的 reaction 留扩展位。
    // 跟 iMessage tapback 6 + Slack 1-row picker 的"主+扩展"分层一致。
    private static let extendedEmojis: [String] = [
        "🤔", "👀", "🙌", "🙏", "👏", "💯",
        "💡", "✅", "❌", "⚠️", "✨", "💪"
    ]

    /// Long-press v3 preview —— `.contextMenu(menuItems:preview:)` 触发时
    /// 系统自动用此 view 做 zoom-in 弹动画(参考 iMessage)。同样的气泡
    /// body,套白色 surfacePrimary 背景增强 "突出" 感。
    @ViewBuilder
    private func enlargedPreview(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: BsSpacing.xs) {
            if !msg.content.isEmpty {
                Text(ChatContentHighlighter.attributed(
                    msg.content,
                    mentionColor: isCurrentUser ? BsColor.brandCoral : BsColor.brandAzure
                ))
                    .font(BsTypography.body)
                    .padding(.horizontal, BsSpacing.lg)
                    .padding(.vertical, BsSpacing.sm + 2)
                    .glassEffect(
                        isCurrentUser
                            ? .regular.tint(BsColor.brandAzure.opacity(0.18))
                            : .regular,
                        in: bubbleShape(isCurrentUser: isCurrentUser)
                    )
                    .foregroundStyle(BsColor.ink)
            }

            // 附件展示用缩略形态保留,放在 preview 里能让用户更直观看到
            // "我要对哪条消息操作"。
            ForEach(msg.attachments, id: \.url) { att in
                attachmentView(att)
            }

            let timeText = ChatDateFormatter.format(msg.createdAt)
            if !timeText.isEmpty {
                Text(timeText)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(BsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
    }

    // MARK: - Iter 7 Phase 1.2: Inline edit bubble

    @ViewBuilder
    private func inlineEditBubble(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        VStack(alignment: .trailing, spacing: BsSpacing.xs) {
            TextField("编辑消息…", text: $viewModel.editingDraft, axis: .vertical)
                .font(BsTypography.body)
                .lineLimit(1...6)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .fill(BsColor.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.brandAzure.opacity(0.4), lineWidth: 1)
                )
            HStack(spacing: BsSpacing.sm) {
                Button("取消") {
                    Haptic.light()
                    viewModel.cancelEditing()
                }
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)

                Button("保存") {
                    Haptic.medium()
                    Task { await viewModel.commitEdit() }
                }
                .font(BsTypography.captionSmall.weight(.semibold))
                .foregroundStyle(BsColor.brandAzure)
            }
        }
    }

    // MARK: - Iter 7 Phase 1.2: Read receipt avatar stack

    @ViewBuilder
    private func readReceiptStack(readers: [UUID]) -> some View {
        // 仅显示 max 3 个头像 + (剩余数字)。点击 future: open sheet with full list.
        let visible = Array(readers.prefix(3))
        let extra = max(0, readers.count - visible.count)
        HStack(spacing: -8) {
            ForEach(visible, id: \.self) { uid in
                readerAvatar(userId: uid)
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BsColor.surfacePrimary, lineWidth: 1.5))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BsColor.inkMuted)
                    .padding(.leading, 10)
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func readerAvatar(userId: UUID) -> some View {
        // Reader avatars rely on mentionCandidates lookup we already preload.
        // If the reader isn't in the candidate list (cross-channel cache miss)
        // we fall back to a tinted initial circle — RPC return ordering is
        // by user_id, so the position is stable.
        if let p = viewModel.mentionCandidates.first(where: { $0.id == userId }),
           let urlStr = p.avatarUrl,
           let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    BsColor.brandAzure.opacity(0.25)
                }
            }
        } else {
            BsColor.brandAzure.opacity(0.25)
        }
    }

    // MARK: - Iter 7 Phase 1.2: Link preview cache (per-bubble fetcher)

    /// Singleton-per-URL fetcher cache so re-rendering doesn't refetch.
    @State private var linkPreviewFetchers: [URL: LinkPreviewFetcher] = [:]

    private func linkPreviewFetcher(for url: URL) -> LinkPreviewFetcher {
        if let existing = linkPreviewFetchers[url] { return existing }
        let f = LinkPreviewFetcher()
        // Async-safe write on main actor (helper is @State, we mutate through
        // mainactor-bound view body context).
        DispatchQueue.main.async {
            linkPreviewFetchers[url] = f
        }
        return f
    }

    /// Phase 4.5: 呈现 reaction 芯片 —— 每个 emoji 是一个可 tap 的 chip，显示
    /// 计数；当前用户已投票的 chip 高亮。对齐 Web page.tsx:772-790。
    @ViewBuilder
    private func reactionChipRow(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        // Dictionary 顺序不稳定，手动按 emoji 排序让同一条消息的 chip 顺序稳定。
        let entries = msg.reactions.sorted(by: { $0.key < $1.key })
        HStack(spacing: 6) {
            ForEach(entries, id: \.key) { emoji, userIds in
                let mineAlready = viewModel.currentUserId.map { userIds.contains($0) } ?? false
                Button {
                    Task { await viewModel.toggleReaction(messageId: msg.id, emoji: emoji) }
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji)
                        Text("\(userIds.count)")
                            .font(BsTypography.captionSmall)
                    }
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            mineAlready
                                ? BsColor.brandAzure.opacity(0.15)
                                : BsColor.surfaceTertiary
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            mineAlready ? BsColor.brandAzure.opacity(0.4) : BsColor.borderSubtle,
                            lineWidth: 0.5
                        )
                    )
                    .foregroundStyle(mineAlready ? BsColor.brandAzure : BsColor.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func attachmentView(_ att: ChatAttachment) -> some View {
        // Web 渲染：image 用 <img> 200x200 cover + 点击新 tab；
        // file 用 FileText 图标 + 文件名。iOS 对齐：AsyncImage / SF 图标，
        // 点击用 Link 打开 URL（Safari 或系统文档预览）。
        if let url = URL(string: att.url) {
            Link(destination: url) {
                if att.isImage {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                BsColor.surfaceTertiary
                                ProgressView()
                            }
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                BsColor.surfaceTertiary
                                Image(systemName: "photo")
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                } else {
                    HStack(spacing: BsSpacing.sm) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(BsColor.brandAzure)
                        Text(att.name)
                            .font(BsTypography.bodySmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(BsColor.ink)
                    }
                    .padding(.horizontal, BsSpacing.md)
                    .padding(.vertical, BsSpacing.sm + 2)
                    .background(BsColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Supporting types

/// 本地 pending 上传项——等用户点"发送"时才真正上传到 chat-files。
/// 带 previewImage 是为了在预览条里即时显示缩略图而不用再解码一次。
private struct PendingUpload: Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
    let mimeType: String
    let previewImage: UIImage?
}
