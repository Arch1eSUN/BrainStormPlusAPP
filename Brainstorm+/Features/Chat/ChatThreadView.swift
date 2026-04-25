import SwiftUI
import Combine
import Supabase

/// Phase 1.1 — Thread 视图
///
/// 当用户在 ChatRoomView 里点击消息底部的 "n 条回复 →" footer,这个 sheet 弹出。
/// 顶部固定显示 parent 消息(气泡形态,跟主流相同语言);下方滚动显示所有
/// reply_to == parent.id 的子消息;底部独立的输入栏发送 reply(reply_to 自动
/// 填 parent.id)。
///
/// Supabase 查询: `chat_messages WHERE reply_to = parent.id ORDER BY created_at`
/// + Realtime 订阅同 channel(parent.channelId)的 INSERT 事件,过滤客户端
/// 仅展示 reply_to == parent.id 的行。
@MainActor
public final class ChatThreadViewModel: ObservableObject {
    @Published var parent: ChatMessage
    @Published var replies: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String? = nil

    let channel: ChatChannel
    let currentUserId: UUID?
    private let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    init(client: SupabaseClient, channel: ChatChannel, parent: ChatMessage, currentUserId: UUID?) {
        self.client = client
        self.channel = channel
        self.parent = parent
        self.currentUserId = currentUserId
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        await fetchReplies()
        await subscribeRealtime()
    }

    func fetchReplies() async {
        do {
            let rows: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("reply_to", value: parent.id.uuidString)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
            self.replies = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    func sendReply(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let userId = currentUserId else {
            errorMessage = "未登录"
            return
        }
        isSending = true
        defer { isSending = false }

        struct InsertPayload: Encodable {
            let channel_id: String
            let sender_id: String
            let content: String
            let type: String
            let attachments: [ChatAttachment]
            let reply_to: String?
        }

        // Optimistic append: 用临时 UUID,realtime 回来后按 id 去重。
        let optimisticId = UUID()
        let optimistic = ChatMessage(
            id: optimisticId,
            channelId: channel.id,
            senderId: userId,
            content: trimmed,
            type: .text,
            replyTo: parent.id,
            attachments: [],
            reactions: [:],
            isWithdrawn: false,
            withdrawnAt: nil,
            createdAt: Date(),
            threadReplyCount: 0
        )
        replies.append(optimistic)

        do {
            let inserted: ChatMessage = try await client
                .from("chat_messages")
                .insert(InsertPayload(
                    channel_id: channel.id.uuidString,
                    sender_id: userId.uuidString,
                    content: trimmed,
                    type: "text",
                    attachments: [],
                    reply_to: parent.id.uuidString
                ))
                .select()
                .single()
                .execute()
                .value

            // 用 server 真值替换乐观行(按 optimisticId 找位)。
            if let idx = replies.firstIndex(where: { $0.id == optimisticId }) {
                replies[idx] = inserted
            }
            // 父消息计数 +1(本地立即生效,realtime UPDATE 在某些环境下不会
            // 投递这种 trigger 改动,所以乐观即可)
            parent = ChatMessage(
                id: parent.id,
                channelId: parent.channelId,
                senderId: parent.senderId,
                content: parent.content,
                type: parent.type,
                replyTo: parent.replyTo,
                attachments: parent.attachments,
                reactions: parent.reactions,
                isWithdrawn: parent.isWithdrawn,
                withdrawnAt: parent.withdrawnAt,
                createdAt: parent.createdAt,
                threadReplyCount: parent.threadReplyCount + 1
            )
        } catch {
            // 回滚乐观行
            replies.removeAll { $0.id == optimisticId }
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    private func subscribeRealtime() async {
        teardown()
        let ch = client.channel("realtime-thread-\(parent.id.uuidString)")
        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: .eq("reply_to", value: parent.id.uuidString)
        )
        let updates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "chat_messages",
            filter: .eq("reply_to", value: parent.id.uuidString)
        )
        self.realtimeChannel = ch
        do {
            try await ch.subscribeWithError()
        } catch {
            errorMessage = "实时连接失败"
        }
        self.realtimeTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await change in inserts {
                        if let msg: ChatMessage = try? change.record.decode(as: ChatMessage.self) {
                            await MainActor.run { self?.handleInsert(msg) }
                        }
                    }
                }
                group.addTask { [weak self] in
                    for await change in updates {
                        if let msg: ChatMessage = try? change.record.decode(as: ChatMessage.self) {
                            await MainActor.run { self?.handleUpdate(msg) }
                        }
                    }
                }
            }
        }
    }

    private func handleInsert(_ row: ChatMessage) {
        guard !replies.contains(where: { $0.id == row.id }) else { return }
        replies.append(row)
    }

    private func handleUpdate(_ row: ChatMessage) {
        if let idx = replies.firstIndex(where: { $0.id == row.id }) {
            replies[idx] = row
        }
    }

    func teardown() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            Task { [client] in await client.removeChannel(ch) }
            realtimeChannel = nil
        }
    }

    deinit {
        realtimeTask?.cancel()
    }
}

public struct ChatThreadView: View {
    @StateObject private var vm: ChatThreadViewModel
    @State private var draftText: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(client: SupabaseClient, channel: ChatChannel, parent: ChatMessage, currentUserId: UUID?) {
        _vm = StateObject(wrappedValue: ChatThreadViewModel(
            client: client, channel: channel, parent: parent, currentUserId: currentUserId
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    threadList
                    MessageInputBar(
                        text: $draftText,
                        isSending: vm.isSending,
                        canSend: !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        placeholder: "回复线程…",
                        onSend: send,
                        onAttachmentTap: {},
                        onPhotoTap: {},
                        onEmojiTap: {},
                        onMentionTap: {}
                    )
                }
            }
            .navigationTitle("线程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(BsColor.brandAzure)
                }
            }
            .zyErrorBanner($vm.errorMessage)
            .task { await vm.bootstrap() }
            .onDisappear { vm.teardown() }
        }
    }

    @ViewBuilder
    private var threadList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                // 父消息固定 —— 给一个 "原帖" label 区分
                Text("原帖")
                    .font(BsTypography.label)
                    .foregroundStyle(BsColor.inkMuted)
                    .padding(.top, BsSpacing.md)
                    .padding(.horizontal, BsSpacing.lg)

                threadBubble(msg: vm.parent, isCurrentUser: vm.parent.senderId == vm.currentUserId)
                    .padding(.horizontal, BsSpacing.lg)

                Divider()
                    .padding(.horizontal, BsSpacing.lg)

                if vm.replies.isEmpty && !vm.isLoading {
                    Text("还没有回复 · 第一条由你写下")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .padding(.vertical, BsSpacing.xl)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(vm.replies) { reply in
                        threadBubble(msg: reply, isCurrentUser: reply.senderId == vm.currentUserId)
                            .padding(.horizontal, BsSpacing.lg)
                    }
                }
            }
            .padding(.vertical, BsSpacing.md)
        }
    }

    @ViewBuilder
    private func threadBubble(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 50) }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: BsSpacing.xs) {
                Text(msg.content)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
                    .padding(.horizontal, BsSpacing.lg)
                    .padding(.vertical, BsSpacing.sm + 2)
                    .glassEffect(
                        isCurrentUser
                            ? .regular.tint(BsColor.brandAzure.opacity(0.18))
                            : .regular,
                        in: RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                    )
                if let stamp = msg.createdAt {
                    Text(ChatDateFormatter.format(stamp))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            if !isCurrentUser { Spacer(minLength: 50) }
        }
    }

    private func send() {
        let text = draftText
        draftText = ""
        Task { await vm.sendReply(text) }
    }
}
