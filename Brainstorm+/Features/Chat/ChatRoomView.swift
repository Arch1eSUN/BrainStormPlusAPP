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
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

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
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        } else if viewModel.isLoading && viewModel.messages.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(
                                msg: msg,
                                isCurrentUser: msg.senderId == viewModel.currentUserId
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
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

    private var inputBar: some View {
        HStack(spacing: 12) {
            Menu {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    Label("图片", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("文件", systemImage: "doc")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }

            TextField("Type a message...", text: $messageText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Capsule())

            Button(action: sendTapped) {
                if viewModel.isSending {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isSendDisabled ? .gray : .blue)
                        .rotationEffect(.degrees(45))
                }
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .top
        )
    }

    // MARK: - Pending attachments 预览条

    private var pendingAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingUploads) { upload in
                    ZStack(alignment: .topTrailing) {
                        pendingThumbnail(for: upload)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func pendingThumbnail(for upload: PendingUpload) -> some View {
        if let image = upload.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(UIColor.tertiarySystemBackground)
                VStack(spacing: 2) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                    Text(upload.fileName)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 4)
                        .foregroundColor(.secondary)
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
                    viewModel.errorMessage = "上传失败: \(error.localizedDescription)"
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
                viewModel.errorMessage = "选择文件失败: \(error.localizedDescription)"
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

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sprint 3.4: 如果这是一条回复消息，先画一条 "reply-to" 块。
                // 原消息可能已被撤回（isWithdrawn）或查不到（从 replyLookup 缺席），
                // 两种情况都要降级成占位文本，跟 Web 保持一致。
                if let parentId = msg.replyTo {
                    replyBlock(parentId: parentId, isCurrentUser: isCurrentUser)
                }

                if msg.isWithdrawn {
                    // Web `MessageItem` (page.tsx 渲染逻辑) —— 撤回后只留占位。
                    Text("此消息已撤回")
                        .font(.body.italic())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    // 文本部分：空字符串 + 纯附件时跳过气泡，避免多一个空框。
                    // Sprint 3.5: content 走 `ChatContentHighlighter` 给
                    // `@mention` 套高亮样式。self-bubble 是蓝底白字，mention 用
                    // 黄色；peer-bubble 是浅灰底，mention 用蓝色 —— 需要足够对比
                    // 才能让 mention 可识别。
                    if !msg.content.isEmpty {
                        Text(ChatContentHighlighter.attributed(
                            msg.content,
                            mentionColor: isCurrentUser ? .yellow : .blue
                        ))
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                isCurrentUser
                                    ? Color.blue
                                    : Color(UIColor.secondarySystemBackground)
                            )
                            .foregroundColor(isCurrentUser ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    ForEach(msg.attachments, id: \.url) { att in
                        attachmentView(att)
                    }
                }

                let timeText = ChatDateFormatter.format(msg.createdAt)
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            // contextMenu: 长按消息气泡弹出 "回复" / "撤回" 菜单。
            // `Withdraw` 只在 own-message + 未撤回 + 2 分钟内 显示 ——
            // 跟 RPC 和 Web page.tsx:386-390 的判据严格一致，避免用户
            // 点出来再被服务端拒绝。
            .contextMenu {
                if !msg.isWithdrawn {
                    Button {
                        replyingTo = msg
                    } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    if isCurrentUser && canWithdraw(msg) {
                        Button(role: .destructive) {
                            Task { await viewModel.withdrawMessage(msg.id) }
                        } label: {
                            Label("撤回", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }

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
                .foregroundColor(.gray.opacity(0.4))
            Text(preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Reply preview strip (above input bar)

    private func replyPreviewStrip(parent: ChatMessage) -> some View {
        let preview: String = {
            if parent.isWithdrawn { return "消息已撤回" }
            if !parent.content.isEmpty { return parent.content }
            if !parent.attachments.isEmpty {
                return parent.attachments.allSatisfy({ $0.isImage }) ? "[图片]" : "[文件]"
            }
            return "[消息]"
        }()
        return HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption)
                .foregroundColor(.blue)
            Text("回复: \(preview)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.15)),
            alignment: .top
        )
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
                                Color(UIColor.tertiarySystemBackground)
                                ProgressView()
                            }
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                Color(UIColor.tertiarySystemBackground)
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text(att.name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
