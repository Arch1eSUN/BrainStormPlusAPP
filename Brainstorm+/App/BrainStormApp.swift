import SwiftUI
import Combine
import Supabase

@main
struct BrainStormApp: App {
    @State private var sessionManager = SessionManager()
    @StateObject private var realtimeSync = RealtimeSyncManager.shared
    @State private var minSplashHeld = false

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isLoadingSession || !minSplashHeld {
                    SplashView()
                        .transition(.opacity)
                } else if sessionManager.isAuthenticated {
                    MainTabView()
                        .environment(sessionManager)
                        .environmentObject(realtimeSync)
                        .transition(.opacity)
                } else {
                    LoginView()
                        .environment(sessionManager)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: sessionManager.isLoadingSession)
            .animation(.easeOut(duration: 0.35), value: minSplashHeld)
            .animation(.easeOut(duration: 0.35), value: sessionManager.isAuthenticated)
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
            backgroundLayer

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

    private var backgroundLayer: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

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
