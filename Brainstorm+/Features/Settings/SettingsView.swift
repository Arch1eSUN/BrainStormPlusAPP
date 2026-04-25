import SwiftUI
import Supabase

/// 全局"外观"偏好 key —— `SettingsAppearanceView` 写、`AuthenticatedRoot`
/// 读。三选一：system / light / dark。默认 system。
public enum BsAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// iOS Settings 下"支持"分区里的 3 个外链地址。域名沿用
/// `AppEnvironment.webAPIBaseURL`（DEBUG=127.0.0.1:3000，RELEASE=zyoffice.me）
/// 避免硬编码。Help 先走 mailto fallback，等 Web 上线 `/help` 后替换。
private enum SettingsExternalLink {
    static let privacy = AppEnvironment.webAPIBaseURL.appendingPathComponent("privacy")
    static let terms = AppEnvironment.webAPIBaseURL.appendingPathComponent("terms")
    static let help = URL(string: "mailto:support@zyoffice.me?subject=BrainStorm%2B%20iOS%20帮助反馈")!
}

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingSignOutAlert = false
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage("bs_color_scheme") private var appearanceRaw: String = BsAppearanceMode.system.rawValue

    public init() {}

    private var appearanceLabel: String {
        BsAppearanceMode(rawValue: appearanceRaw)?.displayLabel ?? "跟随系统"
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // v1.1: ambient 弥散彻底退出，纯净 pageBackground（neutral gray）承底
                BsColor.pageBackground.ignoresSafeArea()

                Form {
                    // ── Profile row (tap to edit) ─────────────────────────
                    Section {
                        NavigationLink {
                            SettingsProfileView()
                        } label: {
                            profileRow
                        }
                    }

                    // ── 常规 ─────────────────────────────────────────────
                    Section {
                        NavigationLink {
                            SettingsNotificationsView()
                        } label: {
                            Label {
                                Text("通知偏好")
                            } icon: {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(BsColor.brandCoral)
                            }
                        }

                        // 隐私与安全 —— 链到 Web 隐私政策。iOS 端没有独立的权限
                        // 设置面板（推送 / 位置授权由 iOS 系统设置管），直接跳外链
                        // 比留占位页更诚实。
                        Link(destination: SettingsExternalLink.privacy) {
                            HStack {
                                Label {
                                    Text("隐私与安全")
                                        .foregroundStyle(BsColor.ink)
                                } icon: {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(BsColor.ink)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.footnote)
                                    .foregroundStyle(BsColor.inkFaint)
                            }
                        }

                        NavigationLink {
                            SettingsAppearanceView()
                        } label: {
                            HStack {
                                Label {
                                    Text("外观")
                                } icon: {
                                    Image(systemName: "paintpalette.fill")
                                        .foregroundStyle(BsColor.brandAzure)
                                }
                                Spacer()
                                Text(appearanceLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                    } header: {
                        Text("常规")
                    } footer: {
                        Text("管理系统通知、隐私与外观偏好")
                    }

                    // Phase 25：管理员入口已迁到 Dashboard 工作台"管理"网格。
                    // "我的" tab 回归纯个人区，不再塞功能入口（飞书/钉钉 pattern）。

                    // ── 支持 ─────────────────────────────────────────────
                    Section {
                        // 帮助中心 —— 产品未上线 /help 落地页，fallback 邮件支持。
                        // 等 Web 上线 help 页后，换成 appendingPathComponent("help")。
                        Link(destination: SettingsExternalLink.help) {
                            HStack {
                                Label {
                                    Text("帮助中心")
                                        .foregroundStyle(BsColor.ink)
                                } icon: {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundStyle(BsColor.brandMint)
                                }
                                Spacer()
                                Image(systemName: "envelope")
                                    .font(.footnote)
                                    .foregroundStyle(BsColor.inkFaint)
                            }
                        }

                        Link(destination: SettingsExternalLink.terms) {
                            HStack {
                                Label {
                                    Text("服务条款")
                                        .foregroundStyle(BsColor.ink)
                                } icon: {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(BsColor.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.footnote)
                                    .foregroundStyle(BsColor.inkFaint)
                            }
                        }

                        NavigationLink {
                            SettingsAboutView()
                        } label: {
                            Label {
                                Text("关于 BrainStorm+")
                            } icon: {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(BsColor.brandMint)
                            }
                        }
                    } header: {
                        Text("支持")
                    }

                    // ── 退出登录 ─────────────────────────────────────────
                    Section {
                        Button(role: .destructive) {
                            Haptic.light()
                            showingSignOutAlert = true
                        } label: {
                            Label {
                                Text("退出登录")
                            } icon: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
                // Fusion: kill the Form's grouped gray backdrop so the ambient
                // glow bleeds through the section gaps.
                .scrollContentBackground(.hidden)
            }
            // Tab label is "我的" — mirror it here for a more personal nav
            // title rather than the utilitarian "设置".
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadProfile()
            }
            .alert("退出登录", isPresented: $showingSignOutAlert) {
                Button("取消", role: .cancel) { }
                Button("退出登录", role: .destructive) {
                    Haptic.medium()
                    Task {
                        await viewModel.signOut(sessionManager: sessionManager)
                    }
                }
            } message: {
                Text("退出后需要重新登录才能查看考勤、审批与通知。")
            }
        }
    }

    // MARK: - Profile row

    @ViewBuilder
    private var profileRow: some View {
        HStack(spacing: BsSpacing.lg) {
            // Hero avatar — azure glass halo instead of flat mint fill so the
            // Me tab opens with a personal, editorial moment rather than a
            // utilitarian settings row.
            ZStack {
                Circle()
                    .frame(width: 56, height: 56)
                    .glassEffect(
                        .regular.tint(BsColor.brandAzure.opacity(0.10)),
                        in: Circle()
                    )

                // Bug-fix: 不显示 "U" 占位字符。profile 未到货前留空圆（halo），
                // 到货后再渲染姓名首字母，避免 "User" / "U" flash。
                if let initial = viewModel.profile?.fullName?.prefix(1), !initial.isEmpty {
                    Text(String(initial))
                        .font(BsTypography.brandTitle)
                        .foregroundStyle(BsColor.brandAzure)
                        .transition(.opacity)
                }
            }
            .animation(BsMotion.Anim.smooth, value: viewModel.profile?.fullName)

            VStack(alignment: .leading, spacing: 2) {
                // Bug-fix: profile 未到货时用 shimmer 占位行，不写死 "用户" 字面量。
                if let fullName = viewModel.profile?.fullName, !fullName.isEmpty {
                    Text(fullName)
                        .font(BsTypography.brandTitle)
                        .foregroundStyle(BsColor.ink)
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(BsColor.inkFaint.opacity(0.25))
                        .frame(width: 120, height: 18)
                        .shimmering()
                        .transition(.opacity)
                }

                if let email = viewModel.profile?.email, !email.isEmpty {
                    Text(email)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .animation(BsMotion.Anim.smooth, value: viewModel.profile?.fullName)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看并编辑个人资料")
    }

    // v1.1: admin 入口已永久迁到 BsCommandPalette 的"管理"分组。
    // 原 isAdminVisible 守卫已无消费者，一并移除。
}

public struct SettingsRowView: View {
    let icon: String
    var iconColor: Color = BsColor.brandAzure
    let title: String
    let showChevron: Bool

    public var body: some View {
        Button {
            Haptic.light()
        } label: {
            SettingsRowContent(
                icon: icon,
                iconColor: iconColor,
                title: title,
                showChevron: showChevron
            )
        }
        // Use a simple plain style or opacity-changing style internally
        .buttonStyle(SettingsRowButtonStyle())
    }
}

/// Presentational row content shared by `SettingsRowView` (for non-navigating
/// rows) and `NavigationLink` labels (which need a pure view, not a Button).
public struct SettingsRowContent: View {
    let icon: String
    var iconColor: Color = BsColor.brandAzure
    let title: String
    let showChevron: Bool

    public init(icon: String, iconColor: Color = BsColor.brandAzure, title: String, showChevron: Bool) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.showChevron = showChevron
    }

    public var body: some View {
        HStack(spacing: BsSpacing.lg) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(.body))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.ink)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
        .padding(.vertical, BsSpacing.md + 2)
        .padding(.horizontal, BsSpacing.lg)
        .contentShape(Rectangle())
    }
}

// A subtle button style for rows that just dims slightly on press
struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? BsColor.surfaceSecondary.opacity(0.5) : Color.clear)
            .animation(BsMotion.Anim.smooth, value: configuration.isPressed)
    }
}

#Preview {
    SettingsView()
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Appearance picker (Phase 25.c)
// ───────────────────────────────────────────────────────────────────
// 三选一：跟随系统 / 浅色 / 深色。
// 写入 @AppStorage("bs_color_scheme")，`AuthenticatedRoot` 读取后把
// `preferredColorScheme(_:)` 套在整个已登录 view 树上（SplashView +
// LoginView 保持跟随系统以免登录前看到风格跳动）。
// ═══════════════════════════════════════════════════════════════════
public struct SettingsAppearanceView: View {
    @AppStorage("bs_color_scheme") private var appearanceRaw: String = BsAppearanceMode.system.rawValue

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(BsAppearanceMode.allCases) { mode in
                    Button {
                        Haptic.light()
                        appearanceRaw = mode.rawValue
                    } label: {
                        HStack {
                            Label {
                                Text(mode.displayLabel)
                                    .foregroundStyle(BsColor.ink)
                            } icon: {
                                Image(systemName: mode.systemImage)
                                    .foregroundStyle(BsColor.brandAzure)
                            }
                            Spacer()
                            if appearanceRaw == mode.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(BsColor.brandAzure)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("主题")
            } footer: {
                Text("选择 BrainStorm+ 的浅色 / 深色外观。跟随系统时将自动响应 iOS 控制中心的外观切换。")
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - About (Phase 25.c)
// ───────────────────────────────────────────────────────────────────
// 纯本地静态页 —— 不需要服务器：
//   • Logo + BrainStorm+ wordmark
//   • CFBundleShortVersionString + CFBundleVersion 读取
//   • 公司 / 版权 / 1 行 tagline
// ═══════════════════════════════════════════════════════════════════
public struct SettingsAboutView: View {
    public init() {}

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "版本 \(short) (\(build))"
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BsSpacing.xl) {
                VStack(spacing: BsSpacing.md) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .padding(.top, BsSpacing.xl)

                    Text("BrainStorm+")
                        .font(BsTypography.brandWordmark)
                        .foregroundStyle(BsColor.ink)

                    Text(versionText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(BsColor.inkMuted)
                }

                VStack(spacing: BsSpacing.sm) {
                    Text("一个为团队设计的协同操作系统")
                        .font(.footnote)
                        .foregroundStyle(BsColor.inkMuted)
                        .multilineTextAlignment(.center)

                    Text("由致远办公出品")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                }
                .padding(.horizontal, BsSpacing.lg)

                VStack(spacing: 4) {
                    Text("© 2026 BrainStorm+")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkFaint)
                    Text("All Rights Reserved.")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkFaint)
                }
                .padding(.top, BsSpacing.xl)

                Spacer(minLength: BsSpacing.xl)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, BsSpacing.lg)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
