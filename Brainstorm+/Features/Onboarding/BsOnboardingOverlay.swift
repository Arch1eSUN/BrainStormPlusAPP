import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsOnboardingOverlay —— v1.1 首次启动欢迎 overlay
//
// 设计来源：docs/plans/2026-04-24-ios-full-redesign-plan.md §九 Phase 8
//
// 3 步 carousel，介绍 v1.1 的 3 个签名点：
//   1. 欢迎 —— 品牌 logo + wordmark + tagline
//   2. 液体 Hero —— 今日工时一眼可见（signature A 预告）
//   3. 命令面板 —— 所有应用一键直达（signature B 预告）
//
// 展示控制：
//   • 调用方使用 @AppStorage("bs_has_seen_onboarding") 决定是否挂载
//   • overlay 挂载后只读 onDismiss 回调；持久化交给父级
// ══════════════════════════════════════════════════════════════════

public struct BsOnboardingOverlay: View {
    let onDismiss: () -> Void

    @State private var currentStep: Int = 0
    private let totalSteps = 3

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Backdrop —— 半透 pageBackground + ultraThinMaterial 模糊（材质才能真正穿透）
            // 原 opacity 0.98 完全盖死后 material 等于零效果（audit Batch 6 修复）
            BsColor.pageBackground.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Card container (full-screen layout)
            VStack(spacing: 0) {
                // Skip button —— top-right
                HStack {
                    Spacer()
                    Button {
                        Haptic.light()
                        onDismiss()
                    } label: {
                        // Polish: step down to caption weight so the tertiary
                        // "skip" never competes with the primary CTA for focus.
                        Text("跳过")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .accessibilityLabel("跳过引导")
                    .accessibilityHint("直接进入 BrainStorm+ 工作台")
                }
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.xs)

                Spacer()

                // 3-step carousel —— 原生 TabView paging style
                TabView(selection: $currentStep) {
                    WelcomeStep().tag(0)
                    LiquidHeroStep().tag(1)
                    PaletteStep().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                .animation(BsMotion.Anim.smooth, value: currentStep)

                Spacer()

                // Bottom controls —— page dots + primary CTA
                VStack(spacing: BsSpacing.lg) {
                    pageIndicator
                    primaryCTA
                }
                .padding(.horizontal, BsSpacing.xxl)
                .padding(.bottom, BsSpacing.xxl)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentStep ? BsColor.brandAzure : BsColor.inkFaint.opacity(0.3))
                    .frame(width: idx == currentStep ? 22 : 8, height: 8)
                    .animation(BsMotion.Anim.overshoot, value: currentStep)
                    // Polish: let users tap a dot to jump — improves discovery
                    // without stealing weight from the primary CTA.
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture {
                        guard idx != currentStep else { return }
                        Haptic.soft()
                        withAnimation(BsMotion.Anim.overshoot) { currentStep = idx }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("引导进度")
        .accessibilityValue("第 \(currentStep + 1) 步，共 \(totalSteps) 步")
    }

    // MARK: - Primary CTA

    private var primaryCTA: some View {
        BsPrimaryButton(
            currentStep == totalSteps - 1 ? "开始使用" : "下一步",
            size: .large
        ) {
            Haptic.medium()
            if currentStep < totalSteps - 1 {
                withAnimation(BsMotion.Anim.overshoot) {
                    currentStep += 1
                }
            } else {
                onDismiss()
            }
        }
    }
}

// ── Individual step views ─────────────────────────────────────────

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)

            VStack(spacing: 10) {
                Text("BrainStorm+")
                    .font(.custom("Outfit-Bold", size: 34, relativeTo: .largeTitle))
                    .foregroundStyle(BsColor.ink)

                Text("灵感工作，轻松启动")
                    .font(.custom("Inter-Regular", size: 17, relativeTo: .title3))
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
            }

            Text("焕新版本为你带来液体首屏、命令面板与统一设计语言。")
                .font(.custom("Inter-Regular", size: 15, relativeTo: .body))
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiquidHeroStep: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.14))
                    .frame(width: 128, height: 128)
                Image(systemName: "drop.halffull")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(BsColor.brandAzure)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 12) {
                Text("液体一眼看到今日工时")
                    .font(.custom("Outfit-Bold", size: 26, relativeTo: .title))
                    .foregroundStyle(BsColor.ink)
                    .multilineTextAlignment(.center)

                Text("首页顶部的液体卡 = 你的今日进度。液面越满工时越多，打卡完成变绿，加班变橙。手机倾斜液面还会跟着摇。")
                    .font(.custom("Inter-Regular", size: 16, relativeTo: .body))
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BsSpacing.xl)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaletteStep: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BsColor.brandMint.opacity(0.14))
                    .frame(width: 128, height: 128)
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(BsColor.brandMint)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 12) {
                Text("所有应用一键直达")
                    .font(.custom("Outfit-Bold", size: 26, relativeTo: .title))
                    .foregroundStyle(BsColor.ink)
                    .multilineTextAlignment(.center)

                Text("点击首页顶部 BrainStorm+ 字样，或首页的「所有应用」卡，打开 22+ 应用的命令面板，支持搜索、分类、快速跳转。")
                    .font(.custom("Inter-Regular", size: 16, relativeTo: .body))
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BsSpacing.xl)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    BsOnboardingOverlay(onDismiss: { print("dismissed") })
}
