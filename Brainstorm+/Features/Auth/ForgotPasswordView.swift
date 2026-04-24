import SwiftUI
import Supabase

/// 忘记密码入口。
///
/// 注意：后端逻辑上会真的调用 Supabase `resetPasswordForEmail`（兜底留存能力），
/// 但由于当前所有账号的 email 实际上不被使用（见项目说明 —— email 仅作账号名），
/// UI 成功提示会统一引导用户 "联系管理员重置"，避免让用户傻等一封不会到达的邮件。
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        header

                        if didSubmit {
                            successCard
                        } else {
                            formCard
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("重置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.Brand.primary)
                }
            }
            .onTapGesture { emailFocused = false }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.Brand.primary.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.Brand.primary)
            }

            Text("忘记密码")
                .font(.custom("Outfit-Bold", size: 24, relativeTo: .title2))
                .foregroundStyle(Color.Brand.text)

            Text("请输入账号邮箱，我们会将重置链接发送到您的邮箱。")
                .font(.custom("Inter-Regular", size: 14, relativeTo: .footnote))
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(emailFocused ? Color.Brand.primary : BsColor.inkMuted.opacity(0.5))
                    .font(.system(size: 18))
                    .frame(width: 24)

                TextField("工作邮箱", text: $email)
                    .font(.custom("Inter-Regular", size: 16, relativeTo: .body))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(emailFocused ? Color.Brand.primary : Color.clear, lineWidth: 2)
            )

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(errorMessage)
                        .font(.custom("Inter-Medium", size: 14))
                }
                .foregroundStyle(Color.Brand.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.Brand.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button(action: submit) {
                HStack(spacing: 12) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(isSubmitting ? "提交中…" : "发送重置邮件")
                        .font(.custom("Outfit-Bold", size: 17, relativeTo: .body))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.Brand.primary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.Brand.primary.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(SquishyButtonStyle())
            .disabled(isSubmitting || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
        }
    }

    private var successCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.primary.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.Brand.primary)
            }
            .padding(.top, 8)

            Text("请求已提交")
                .font(.custom("Outfit-Bold", size: 20, relativeTo: .title3))
                .foregroundStyle(Color.Brand.text)

            // 兜底文案：当前 email 不作为真实通知通道，引导联系管理员。
            // 同时也保留"如果邮箱已注册..."措辞以兼容未来真实邮件流。
            Text("如您的邮箱已注册且可收信，重置链接将发送至您的邮箱。\n\n如需更快处理，请联系管理员协助重置密码。")
                .font(.custom("Inter-Regular", size: 14, relativeTo: .footnote))
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Button {
                dismiss()
            } label: {
                Text("返回登录")
                    .font(.custom("Outfit-Bold", size: 17, relativeTo: .body))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.Brand.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.Brand.primary.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(SquishyButtonStyle())
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    // MARK: - Actions

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        HapticManager.shared.trigger(.medium)
        emailFocused = false
        errorMessage = nil

        withAnimation(.spring()) { isSubmitting = true }

        Task {
            do {
                // 真实调用 Supabase 重置密码邮件接口（兜底安全网）。
                // 当前 email 通道可能 degraded，成功提示仍引导联系管理员。
                try await supabase.auth.resetPasswordForEmail(trimmed)
                await MainActor.run {
                    withAnimation {
                        isSubmitting = false
                        didSubmit = true
                    }
                    HapticManager.shared.trigger(.success)
                }
            } catch {
                await MainActor.run {
                    withAnimation { isSubmitting = false }
                    // 即便失败也不泄露邮箱是否存在 —— 统一进入成功态
                    // （匹配 Supabase 默认"不泄露账号存在性"行为）。
                    // 仅在明显的网络错误时才展示错误横幅。
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain {
                        errorMessage = "网络错误，请重试"
                        HapticManager.shared.trigger(.error)
                    } else {
                        withAnimation { didSubmit = true }
                        HapticManager.shared.trigger(.success)
                    }
                }
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
}
