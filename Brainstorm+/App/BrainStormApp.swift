import SwiftUI
import Combine
import Supabase
import UIKit
import UserNotifications

@main
struct BrainStormApp: App {
    // AppDelegate 适配器 —— SwiftUI App 模式下接管 APNS 注册/回调。
    // iOS 26 SwiftUI 没有原生 push hook，必须借 UIApplicationDelegate。
    @UIApplicationDelegateAdaptor(BsAppDelegate.self) private var appDelegate

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

    // Phase 25.c — 外观偏好（跟随系统 / 浅色 / 深色）持久在 AppStorage。
    // 把 override 套在 AuthenticatedRoot 而不是 @main 级别，是因为登录前
    // （SplashView / LoginView）保持跟随系统可以少一次 color scheme 跳动。
    @AppStorage("bs_color_scheme") private var appearanceRaw: String = BsAppearanceMode.system.rawValue

    private var appearance: BsAppearanceMode {
        BsAppearanceMode(rawValue: appearanceRaw) ?? .system
    }

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
            .preferredColorScheme(appearance.preferredColorScheme)
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

// ══════════════════════════════════════════════════════════════════
// BsAppDelegate — APNS 注册 + 通知前台展示 + tap 深链 hook
// ------------------------------------------------------------------
// 1. didFinishLaunchingWithOptions:
//    - 接管 UNUserNotificationCenter delegate
//    - 请求 [.alert, .badge, .sound] 权限（替代原 init 里的 .badge-only）
//    - granted 后 main thread 调 registerForRemoteNotifications
//
// 2. didRegisterForRemoteNotificationsWithDeviceToken:
//    - 拿到 Data → hex 字符串 → ApnsTokenSyncer 写入 apns_device_tokens
//    - 注：用户必须已登录，否则 syncer 内部 supabase.auth.session 抛错
//      会 swallow，不影响业务。app 下次冷启动 / 登录后会再次注册触发上传。
//
// 3. willPresent (foreground):
//    - 默认 iOS 在前台 silently 收 push，不弹 banner。这里强制显示。
//
// 4. didReceive (tap):
//    - userInfo["link"] 是 dispatcher 写进 payload 的深链 path
//    - 现在只 console 打印作 hook，等 router 接好再换成 NotificationCenter post
// ══════════════════════════════════════════════════════════════════
final class BsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                print("[APNS] authorization error:", error)
            }
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("[APNS] authorization denied")
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNS] device token:", token.prefix(8), "…")
        Task { await ApnsTokenSyncer.shared.upload(token: token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNS] registration failed:", error)
    }

    // foreground 收到 push 时强制显示 banner —— 否则 iOS 默认 silent。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    // 用户 tap 通知时，解析 userInfo["link"] 跳对应深链。目前先打印作占位 hook，
    // 后续接上 router/NotificationCenter post 时这里发 deeplink 事件。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("[APNS] tapped userInfo:", userInfo)
        completionHandler()
    }
}
