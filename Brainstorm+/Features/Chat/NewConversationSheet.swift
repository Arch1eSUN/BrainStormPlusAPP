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
                        Divider()
                    }

                    UserPickerView(viewModel: viewModel, selectedUserIds: $selectedUserIds)
                }
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        Haptic.light()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.medium()
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(submitLabel).bold()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .onChange(of: selectedUserIds) { _, _ in Haptic.light() }
            .alert("创建失败", isPresented: errorBinding, actions: {
                Button("好", role: .cancel) { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
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
