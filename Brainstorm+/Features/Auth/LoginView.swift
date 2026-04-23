import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// LoginView — BrainStorm+ 登录页
//
// 设计方针:
//   • Web DNA 保留:Outfit/Inter、Azure/Mint/Coral、Ink 主按钮、几何感
//   • iOS 26 Liquid Glass 材质:登录卡 + 输入框用真·.glassEffect(...)
//     不再是 iOS 15 的 .ultraThinMaterial 手搓
//   • 原生布局:无 web hero、无 footer、Logo + 标题 + 表单 + 贴底按钮
//   • 原生交互:.scrollDismissesKeyboard、touch press feedback、haptic、
//     focus spring、错误 shake + haptic
//   • Dark Mode 自动适配(BsColor dynamic 双值)
// ══════════════════════════════════════════════════════════════════

struct LoginView: View {
    @Environment(SessionManager.self) private var sessionManager

    @State private var account = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false
    @State private var shakeTrigger: CGFloat = 0
    @State private var didAppear = false

    @FocusState private var focusedField: Field?

    @Namespace private var glassNamespace

    enum Field { case account, password }

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .onAppear {
            withAnimation(BsMotion.Anim.entrance.delay(0.05)) {
                didAppear = true
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .animation(BsMotion.Anim.standard, value: focusedField)
        .animation(BsMotion.Anim.smooth, value: errorMessage)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            // Subtle brand tint — radial gradient under the card.
            // 不再是 3 个装饰 blob，而是两层极淡的品牌色做 ambient tint，
            // 让 Liquid Glass 折射有色彩可取。
            RadialGradient(
                colors: [BsColor.brandAzure.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [BsColor.brandMint.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Content

    private var contentLayer: some View {
        GlassEffectContainer(spacing: 16) {
            ScrollView {
                VStack(spacing: BsSpacing.xxl) {
                    Spacer(minLength: BsSpacing.xxl)

                    brandBlock
                        .staggeredAppear(index: 0, isVisible: didAppear)

                    formBlock
                        .staggeredAppear(index: 1, isVisible: didAppear)
                        .bsShake(trigger: shakeTrigger)

                    submitBlock
                        .staggeredAppear(index: 2, isVisible: didAppear)

                    registerHint
                        .staggeredAppear(index: 3, isVisible: didAppear)

                    Spacer(minLength: BsSpacing.xl)
                }
                .padding(.horizontal, BsSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Brand block (Logo + wordmark + welcome)

    private var brandBlock: some View {
        VStack(spacing: BsSpacing.md) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)

            Text("BrainStorm+")
                .font(BsTypography.brandWordmark)
                .foregroundStyle(BsColor.ink)

            VStack(spacing: BsSpacing.xs) {
                Text("欢迎回来")
                    .font(BsTypography.brandDisplay)
                    .foregroundStyle(BsColor.ink)

                Text("登入您的数字化办公中心")
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .padding(.top, BsSpacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Form block

    private var formBlock: some View {
        VStack(spacing: BsSpacing.lg) {
            if let errorMessage {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(errorMessage)
                        .font(BsTypography.caption)
                }
                .foregroundStyle(BsColor.danger)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.sm + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular.tint(BsColor.danger.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            liquidField(
                label: "工作邮箱 / 用户名",
                field: .account
            ) {
                TextField("you@company.com", text: $account)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .account)
                    .onChange(of: focusedField) { _, new in
                        if new == .account { Haptic.soft() }
                    }
            }

            liquidField(
                label: "密码",
                trailingLabel: "忘记密码?",
                trailingAction: {
                    Haptic.soft()
                    focusedField = nil
                    showForgotPassword = true
                },
                field: .password
            ) {
                SecureField("••••••••", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onChange(of: focusedField) { _, new in
                        if new == .password { Haptic.soft() }
                    }
            }
        }
    }

    // Liquid Glass clear-tinted input — 当前 focused 时 tint 升级到 azure
    // Polish: label 色彩 + scale 微幅 + glow ring 三路联动焦点感
    @ViewBuilder
    private func liquidField<Input: View>(
        label: String,
        trailingLabel: String? = nil,
        trailingAction: (() -> Void)? = nil,
        field: Field,
        @ViewBuilder input: () -> Input
    ) -> some View {
        let isFocused = (focusedField == field)
        VStack(alignment: .leading, spacing: BsSpacing.xs + 2) {
            HStack {
                Text(label)
                    .font(BsTypography.label)
                    // Focus 联动:label 色 grey → azure
                    .foregroundStyle(isFocused ? BsColor.brandAzure : BsColor.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                if let trailingLabel, let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailingLabel)
                            .font(BsTypography.label)
                            .foregroundStyle(BsColor.brandAzure)
                            .textCase(.none)
                    }
                    .buttonStyle(.plain)
                }
            }

            input()
                .font(BsTypography.body)
                .foregroundStyle(BsColor.ink)
                .padding(.horizontal, BsSpacing.lg)
                .padding(.vertical, BsSpacing.md + 2)
                .glassEffect(
                    isFocused
                        ? .regular.tint(BsColor.brandAzure.opacity(0.35)).interactive()
                        : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                )
                .glassEffectID("field_\(field == .account ? "account" : "password")", in: glassNamespace)
                // Polish: focus 时 scale 微幅 + soft azure glow ring, spring 曲线
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md + 3, style: .continuous)
                        .strokeBorder(BsColor.brandAzure.opacity(isFocused ? 0.3 : 0), lineWidth: 3)
                        .blur(radius: 4)
                        .allowsHitTesting(false)
                        .padding(-2)
                )
                .scaleEffect(isFocused ? 1.008 : 1.0)
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isFocused)
        }
    }

    // MARK: - Submit

    private var submitBlock: some View {
        // Phase 20 集中爆发点 —— 登录页唯一一个三色品牌渐变主 CTA。
        // BsBrandButton 内部已包 Haptic.medium + 按压反馈 + 阴影,
        // 所以 handleLogin 里原先的 Haptic.medium() 被移除。
        BsBrandButton(size: .large, isLoading: isLoggingIn) {
            handleLogin()
        } label: {
            HStack(spacing: BsSpacing.sm) {
                Text(isLoggingIn ? "登录中…" : "进入工作台")
                if !isLoggingIn {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
        }
        .disabled(isLoggingIn || account.isEmpty || password.isEmpty)
        .opacity((account.isEmpty || password.isEmpty) ? 0.55 : 1.0)
    }

    // MARK: - Register hint (below submit)

    private var registerHint: some View {
        Text("新员工入职？请联系管理员激活账号")
            .font(BsTypography.caption)
            .foregroundStyle(BsColor.inkMuted)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func handleLogin() {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            triggerShake(message: "请填写完整")
            return
        }

        // BsBrandButton 已在 tap 时发 Haptic.medium(),这里不再重复。
        focusedField = nil
        errorMessage = nil
        withAnimation(BsMotion.Anim.standard) {
            isLoggingIn = true
        }

        Task {
            do {
                let email = try await resolveEmail(for: trimmed)
                try await sessionManager.login(email: email, password: password)
                Haptic.success()
            } catch let err as LoginResolveError {
                await MainActor.run {
                    withAnimation { isLoggingIn = false }
                    triggerShake(message: err.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    withAnimation { isLoggingIn = false }
                    triggerShake(message: ErrorLocalizer.localize(error))
                }
            }
        }
    }

    private func resolveEmail(for account: String) async throws -> String {
        if Self.isEmail(account) { return account }
        let url = AppEnvironment.webAPIBaseURL.appendingPathComponent("api/auth/resolve-username")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": account])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LoginResolveError.network }
        if http.statusCode == 200,
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = payload["email"] as? String,
           !email.isEmpty {
            return email
        }
        throw LoginResolveError.unknownUsername
    }

    private static func isEmail(_ input: String) -> Bool {
        input.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private func triggerShake(message: String) {
        Haptic.error()
        errorMessage = message
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeTrigger += 1
        }
    }
}

// MARK: - Errors

private enum LoginResolveError: LocalizedError {
    case unknownUsername, network
    var errorDescription: String? {
        switch self {
        case .unknownUsername: return "用户名不存在"
        case .network:         return "网络错误，请重试"
        }
    }
}

#Preview {
    LoginView().environment(SessionManager())
}
