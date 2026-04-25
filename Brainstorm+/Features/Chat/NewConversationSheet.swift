import SwiftUI

/// Sheet that drives Sprint 3.2 "new conversation" flow.
///
/// Decides direct vs group based on selection count:
///   - exactly 1 selected user → `findOrCreateDirectChannel(with:)`
///   - 2+ selected users       → `createGroupChannel(name:description:memberIds:)`
///
/// On success it fetches the fresh channel row, inserts it at the top of the
/// parent VM's channel list, and invokes `onCreated` so the parent can dismiss
/// + optionally navigate. Mirrors Web's `chat` page NewConversation modal
/// (src/app/(main)/chat/page.tsx + components/chat/NewConversation.tsx).
public struct NewConversationSheet: View {
    @ObservedObject var viewModel: ChatListViewModel
    let onCreated: (ChatChannel) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedUserIds: Set<UUID> = []
    @State private var groupName: String = ""
    @State private var groupDescription: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public init(viewModel: ChatListViewModel, onCreated: @escaping (ChatChannel) -> Void) {
        self.viewModel = viewModel
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    if selectedUserIds.count >= 2 {
                        groupDetailsSection
                        Divider().opacity(0.4)
                    }

                    UserPickerView(viewModel: viewModel, selectedUserIds: $selectedUserIds)

                    // Bug-fix(创建对话失败 + 视图割裂):
                    // 之前 submit 按钮是 toolbar trailing 一个小 Text,小屏 / 视觉
                    // 不明显,用户经常 tap 不到 / 怀疑没响应。改成底部 sticky
                    // 主按钮 (Capsule + Azure fill 同其他主操作),tap 区域更大,
                    // 有 loading state 反馈。toolbar trailing 留空。
                    bottomSubmitBar
                }
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // Haptic removed: 用户反馈辅助按钮过密震动
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            // Haptic removed: 用户反馈 chip 切换过密震动
            .alert("创建失败", isPresented: errorBinding, actions: {
                Button("好", role: .cancel) { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    // Bottom sticky submit bar —— Slack/iMessage pattern:大主按钮 + 选中数提示
    @ViewBuilder
    private var bottomSubmitBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: BsSpacing.sm) {
                if selectedUserIds.isEmpty {
                    Text("请先选择至少 1 位同事")
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: selectedUserIds.count >= 2 ? "person.3.fill" : "person.fill")
                            .font(.caption)
                            .foregroundStyle(BsColor.brandAzure)
                        Text(selectedUserIds.count >= 2
                             ? "群聊 · 已选 \(selectedUserIds.count) 人"
                             : "私聊")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                Spacer()

                Button {
                    Haptic.medium() // 关键 mutation：创建会话
                    Task { await submit() }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: selectedUserIds.count >= 2 ? "plus.message.fill" : "bubble.left.and.bubble.right.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(submitLabel)
                            .font(BsTypography.bodySmall.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(canSubmit ? BsColor.brandAzure : BsColor.inkFaint.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
            .background(BsColor.surfacePrimary)
        }
    }

    @ViewBuilder
    private var groupDetailsSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            Text("群聊信息")
                .font(BsTypography.cardTitle)
                .foregroundStyle(BsColor.ink)
            TextField("群名称 (必填)", text: $groupName)
                .textFieldStyle(.roundedBorder)
            TextField("群描述 (可选)", text: $groupDescription)
                .textFieldStyle(.roundedBorder)
        }
        .padding(BsSpacing.lg)
    }

    private var submitLabel: String {
        selectedUserIds.count <= 1 ? "开始聊天" : "创建群聊"
    }

    private var canSubmit: Bool {
        guard !isSubmitting, !selectedUserIds.isEmpty else { return false }
        if selectedUserIds.count >= 2 {
            return !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let channelId: UUID
            if selectedUserIds.count == 1, let other = selectedUserIds.first {
                channelId = try await viewModel.findOrCreateDirectChannel(with: other)
            } else {
                let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDesc = groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                channelId = try await viewModel.createGroupChannel(
                    name: trimmedName,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    memberIds: Array(selectedUserIds)
                )
            }

            let channel = try await viewModel.fetchChannel(id: channelId)
            viewModel.appendChannelIfMissing(channel)
            Haptic.success()
            onCreated(channel)
            dismiss()
        } catch {
            Haptic.error()
            errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
