import SwiftUI
import Combine

public struct ChatRoomView: View {
    @StateObject private var viewModel: ChatRoomViewModel
    @State private var messageText: String = ""

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
                    inputBar
                }
            }
        }
        .navigationTitle(viewModel.channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .task { await viewModel.bootstrap() }
        .onDisappear { viewModel.teardown() }
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

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button(action: {}) {
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

    private var isSendDisabled: Bool {
        viewModel.isSending
            || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendTapped() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""  // optimistic 清，用户立即可以打新消息
        Task { await viewModel.sendMessage(text) }
    }

    @ViewBuilder
    private func messageBubble(msg: ChatMessage, isCurrentUser: Bool) -> some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 50) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(msg.content)
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

                let timeText = ChatDateFormatter.format(msg.createdAt)
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !isCurrentUser { Spacer(minLength: 50) }
        }
    }
}
