import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers

public struct ChatRoomView: View {
    @StateObject private var viewModel: ChatRoomViewModel
    @State private var messageText: String = ""

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

    public init(viewModel: ChatRoomViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            // 纯净 pageBackground —— 气泡 glass tint 漂在上方。
            BsColor.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                content

                if !viewModel.accessDenied {
                    if let parent = replyingTo {
                        replyPreviewStrip(parent: parent)
                    }
                    if !pendingUploads.isEmpty {
                        pendingAttachmentsStrip
                    }
                    inputBar
                }
            }
        }
        .navigationTitle(viewModel.channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .task { await viewModel.bootstrap() }
        .onDisappear { viewModel.teardown() }
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
                ScrollView {
                    LazyVStack(spacing: BsSpacing.md) {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(
                                msg: msg,
                                isCurrentUser: msg.senderId == viewModel.currentUserId
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, BsSpacing.lg)
                    .padding(.vertical, BsSpacing.md)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input bar
    // iOS 26 Liquid Glass composer — 真·.glassEffect(...)，不再是手搓
    // ultraThinMaterial。顶部 hairline 保留分隔感，贴底 safe-area。

    private var inputBar: some View {
        HStack(spacing: BsSpacing.md) {
            Menu {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    Label("图片", systemImage: "photo")
                }
                Button {
                    // Haptic removed: 用户反馈菜单按钮过密震动
                    showFileImporter = true
                } label: {
                    Label("文件", systemImage: "doc")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(BsColor.inkMuted)
            }
            .accessibilityLabel("附件")

            TextField("输入消息…", text: $messageText)
                .font(BsTypography.body)
                .foregroundStyle(BsColor.ink)
                .padding(.horizontal, BsSpacing.lg)
                .padding(.vertical, BsSpacing.sm + 2)
                .background(BsColor.surfaceSecondary)
                .clipShape(Capsule())

            // Send button —— Azure glass-tinted Circle（取代原来光 SF symbol）。
            // 禁用时 tint 几乎透明；激活时品牌 Azure 气场。
            Button(action: sendTapped) {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSendDisabled ? BsColor.inkMuted : BsColor.brandAzure)
                            .rotationEffect(.degrees(45))
                    }
                }
                .frame(width: 36, height: 36)
                .glassEffect(
                    .regular
                        .tint(
                            isSendDisabled
                                ? BsColor.inkFaint.opacity(0.10)
                                : BsColor.brandAzure.opacity(0.35)
                        )
                        .interactive(),
                    in: Circle()
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(isSendDisabled)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.md)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(BsColor.borderSubtle),
            alignment: .top
        )
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

    private var isSendDisabled: Bool {
        if viewModel.isSending { return true }
        let empty = messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return empty && pendingUploads.isEmpty
    }

    private func sendTapped() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let uploads = pendingUploads
        let replyToId = replyingTo?.id
        guard !text.isEmpty || !uploads.isEmpty else { return }
        Haptic.medium()

        // 乐观清 UI —— 如果上传/发送失败，errorMessage 会弹出 banner，
        // 用户可以重新选文件再发。Web 行为一致（page.tsx:301-306）。
        messageText = ""
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
                } else {
                    // 文本部分：空字符串 + 纯附件时跳过气泡，避免多一个空框。
                    // Sprint 3.5: content 走 `ChatContentHighlighter` 给
                    // `@mention` 套高亮样式。
                    //
                    // Fusion 升级：自己一侧 → Azure glass tint + 非对称气泡
                    // (bottomTrailing 4pt 收角，iMessage own-side 形状但带品牌色)；
                    // 对方一侧 → neutral glass + bottomLeading 4pt 收角。
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

                    // Phase 4.5: reaction 芯片条 —— 对齐 Web page.tsx:773-790。
                    if !msg.reactions.isEmpty {
                        reactionChipRow(msg: msg, isCurrentUser: isCurrentUser)
                    }
                }

                let timeText = ChatDateFormatter.format(msg.createdAt)
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
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

                        if !msg.content.isEmpty {
                            Button {
                                UIPasteboard.general.string = msg.content
                                Haptic.light()
                            } label: {
                                Label("复制文本", systemImage: "doc.on.doc")
                            }
                        }

                        // 仅别人的消息显示 @提及 / 转发
                        if !isCurrentUser {
                            Button {
                                replyingTo = msg
                                if !messageText.hasPrefix("@") {
                                    messageText = "@" + messageText
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
