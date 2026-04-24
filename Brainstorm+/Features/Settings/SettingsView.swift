import SwiftUI
import Supabase

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingSignOutAlert = false
    @Environment(SessionManager.self) private var sessionManager

    public init() {}

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

                        Label {
                            Text("隐私与安全")
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(BsColor.ink)
                        }

                        Label {
                            Text("外观")
                        } icon: {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(BsColor.brandAzure)
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
                        Label {
                            Text("帮助中心")
                        } icon: {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(BsColor.brandMint)
                        }

                        Label {
                            Text("服务条款")
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(BsColor.inkMuted)
                        }

                        Label {
                            Text("关于 BrainStorm+")
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(BsColor.brandMint)
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
                Text("确定要退出 BrainStorm+ 吗？")
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

                Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                    .font(BsTypography.brandTitle)
                    .foregroundStyle(BsColor.brandAzure)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.profile?.fullName ?? "用户")
                    .font(BsTypography.brandTitle)
                    .foregroundStyle(BsColor.ink)

                if let email = viewModel.profile?.email, !email.isEmpty {
                    Text(email)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
        .padding(.vertical, 20)
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
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.ink)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
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
