import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4d — Settings → 个人资料 (SwiftUI Form mirror of Web)
//
// Parity with `/dashboard/settings` profile card:
//   - Editable: full_name / display_name / phone / department / position
//   - Read-only: email, role badge
//   - Permission gate: `canEditProfile` (superadmin OR hr_ops cap) —
//     the form disables all inputs and shows an amber notice for
//     non-privileged users, matching Web's gray `cursor-not-allowed` state.
//
// Avatar upload is intentionally NOT included — Web's settings page does
// not expose it either (see C.4d scope notes).
// ══════════════════════════════════════════════════════════════════

public struct SettingsProfileView: View {
    @StateObject private var viewModel = SettingsProfileViewModel()

    // TODO: promote to BsMotion.bannerDuration when Shared editing allowed
    private static let toastDuration: TimeInterval = 2.2

    public init() {}

    public var body: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            Form {
                permissionNotice

                profileSection

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(BsTypography.bodySmall)
                            .foregroundStyle(BsColor.warning)
                    }
                }

                if viewModel.canEditProfile {
                    Section {
                        saveButton
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if viewModel.savedSuccessfully {
                savedBanner.padding(.top, BsSpacing.sm)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var permissionNotice: some View {
        Section {
            HStack(alignment: .top, spacing: BsSpacing.sm + 2) {
                Image(systemName: viewModel.canEditProfile ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(viewModel.canEditProfile ? BsColor.success : BsColor.warning)
                Text(viewModel.canEditProfile
                     ? "你当前拥有员工资料编辑权限，可维护姓名、联系方式、部门和职位信息。"
                     : "仅 Super Admin 或 HR Ops 可编辑员工个人信息；其他字段仅供查看。")
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.ink)
            }
            .padding(.vertical, BsSpacing.xs + 2)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section {
            // Read-only: email
            HStack {
                Text("邮箱")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
                Text(viewModel.email ?? "—")
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
            }

            // Read-only: role
            HStack {
                Text("角色")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
                Text(viewModel.role?.capitalized ?? "—")
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
            }

            // Editable fields
            editableField(label: "姓名", text: $viewModel.fullName, placeholder: "请输入真实姓名", contentType: .name)
            editableField(label: "显示名称", text: $viewModel.displayName, placeholder: "同事看到的昵称（可选）", contentType: .nickname)
            editableField(
                label: "电话",
                text: $viewModel.phone,
                placeholder: "11 位手机号",
                keyboard: .phonePad,
                contentType: .telephoneNumber
            )
            editableField(label: "部门", text: $viewModel.department, placeholder: "例：产品部 / 技术部", contentType: .organizationName)
            editableField(label: "职位", text: $viewModel.position, placeholder: "例：产品经理 / iOS 工程师", contentType: .jobTitle)
        } header: {
            Text("个人资料")
        }
        // iter6 §A.3 — cache 命中后立刻有内容，但服务器返回前给一层
        // skeleton 让用户感知"在刷新"，到货时 .smooth 过渡到真值。
        .redacted(reason: viewModel.isStale && viewModel.isLoading ? .placeholder : [])
        .animation(BsMotion.Anim.smooth, value: viewModel.isStale)
    }

    @ViewBuilder
    private func editableField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: BsSpacing.md) {
            Text(label)
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 72, alignment: .leading)
            TextField(placeholder, text: text)
                .font(BsTypography.body)
                .foregroundStyle(viewModel.canEditProfile ? BsColor.ink : BsColor.inkMuted)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(!viewModel.canEditProfile)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
    }

    // MARK: - Save button

    @ViewBuilder
    private var saveButton: some View {
        Button {
            Haptic.medium()
            Task {
                await viewModel.save()
                if viewModel.savedSuccessfully {
                    Haptic.success()
                }
            }
        } label: {
            HStack(spacing: BsSpacing.sm + 2) {
                if viewModel.isSaving {
                    // Bug-fix(loading 一致性): inline 按钮内 loading 一律 .small。
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(viewModel.isSaving ? "保存中..." : "保存")
            }
        }
        .buttonStyle(BsPrimaryButtonStyle(size: .large, isLoading: viewModel.isSaving))
        .disabled(viewModel.isSaving || viewModel.isLoading)
        .padding(.horizontal, BsSpacing.lg + 4)
        .padding(.vertical, BsSpacing.sm)
    }

    @ViewBuilder
    private var savedBanner: some View {
        HStack(spacing: BsSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BsColor.success)
            Text("个人资料已保存")
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.success)
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(Capsule().fill(BsColor.success.opacity(0.12)))
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            // TODO: promote to BsMotion.bannerDuration when Shared editing allowed
            try? await Task.sleep(for: .seconds(Self.toastDuration))
            viewModel.savedSuccessfully = false
        }
    }
}

#Preview {
    NavigationStack {
        SettingsProfileView()
    }
}
