import SwiftUI
import Combine
import Supabase

@main
struct BrainStormApp: App {
    @State private var sessionManager = SessionManager()
    @StateObject private var realtimeSync = RealtimeSyncManager.shared
    @State private var minSplashHeld = false

    init() {
        // v1.2: TabBar badge 全局走 Coral（unreadBadge = brandCoral）
        UITabBarItem.appearance().badgeColor = UIColor(BsColor.unreadBadge)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isLoadingSession || !minSplashHeld {
                    SplashView()
                        .transition(.opacity)
                } else if sessionManager.isAuthenticated {
                    AuthenticatedRoot()
                        .environment(sessionManager)
                        .environmentObject(realtimeSync)
                        .transition(.opacity)
                } else {
                    LoginView()
                        .environment(sessionManager)
                        .transition(.opacity)
                }
            }
            .animation(BsMotion.Anim.smooth, value: sessionManager.isLoadingSession)
            .animation(BsMotion.Anim.smooth, value: minSplashHeld)
            .animation(BsMotion.Anim.smooth, value: sessionManager.isAuthenticated)
            .task {
                // 并行跑:session check + 最低展示时长(0.9s 让 logo 呼吸 + dots 至少转一圈)
                async let sessionCheck: Void = sessionManager.checkSession()
                async let minHold: () = Task.sleep(for: .milliseconds(900))
                _ = try? await minHold
                _ = await sessionCheck
                minSplashHeld = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseAuthChange"))) { notification in
                // Global fallback for auth states out of band
                Task {
                    await sessionManager.checkSession()
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// AuthenticatedRoot — MainTabView 外壳，负责挂载首次启动 Onboarding
//
// Phase 8：@AppStorage("bs_has_seen_onboarding") 默认 false，首次进入
// 主界面覆盖一层 BsOnboardingOverlay 做 3 步 carousel 介绍（欢迎/液体
// hero/命令面板），用户选「开始使用」或「跳过」后写 true 持久化，
// 后续启动不再出现。
// ──────────────────────────────────────────────────────────────────
private struct AuthenticatedRoot: View {
    @AppStorage("bs_has_seen_onboarding") private var hasSeenOnboarding: Bool = false

    var body: some View {
        MainTabView()
            .overlay {
                if !hasSeenOnboarding {
                    BsOnboardingOverlay {
                        withAnimation(BsMotion.Anim.smooth) {
                            hasSeenOnboarding = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
    }
}

// ──────────────────────────────────────────────────────────────────
// SplashView — 启动态 / session 检查中的第一屏
// • 真·品牌 Logo（BrandLogo imageset，跟 LoginView 一致）
// • Logo 1.6s 缓慢呼吸（scale 1.0 ↔ 1.06，easeInOut 循环）
// • "BrainStorm+" Outfit Bold wordmark
// • 3 dots loading indicator，TimelineView 声明式时间驱动（每 0.35s 流转一步）
// • 背景 paper + azure/mint radial tint，跟 LoginView 的 ambient 保持一致
// • Dark Mode 自动通过 BsColor dynamic 双值响应
// ──────────────────────────────────────────────────────────────────
struct SplashView: View {
    @State private var logoPulse = false

    var body: some View {
        ZStack {
            BsBrandAmbientLayer()

            VStack(spacing: BsSpacing.xl) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .scaleEffect(logoPulse ? 1.06 : 1.0)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        ) { logoPulse = true }
                    }

                Text("BrainStorm+")
                    .font(BsTypography.brandWordmark)
                    .foregroundStyle(BsColor.ink)

                loadingDots
                    .padding(.top, BsSpacing.sm)
            }
        }
    }

    // 原 backgroundLayer 30 LOC 已抽至 Shared/DesignSystem/Primitives/BsBrandAmbientLayer.swift
    // 共用 LoginView + Splash 两处（Batch 0 共享 primitive 建设）

    // 3 个 dots —— TimelineView 声明式驱动，无需 Timer 也无需 State loop
    private var loadingDots: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(BsColor.brandAzure)
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == idx ? 1.35 : 0.75)
                        .opacity(step == idx ? 1.0 : 0.32)
                        .animation(.easeInOut(duration: 0.32), value: step)
                }
            }
        }
    }
}
