import Foundation
import SwiftUI

// ══════════════════════════════════════════════════════════════════
// ErrorPresenter — 错误展示分级 (iter6 §B.2 / iter7 §C.强化 全 app 推广)
//
// 把 raw Error 映射成一个 ErrorTier + 一段面向用户的中文文案。
// VM 层根据 tier 决定 UI 通道：
//   • silent     — 不展示（CancellationError、retry 可恢复）
//   • inline     — 表单字段旁的小红字
//   • banner     — 顶部 toast / .zyErrorBanner（默认通道）
//   • fullscreen — modal（auth required / 关键流程被打断）
//
// Iter 7 §C 推广：所有 VM 的 catch 块都用 ErrorPresenter.userFacingMessage,
// silent tier 自动返回 nil（cancellation 不再 banner 闪屏）；fullscreen tier
// 上层通过 ErrorFullscreenView 触发"重新登录"再走 SessionManager.signOut。
// ══════════════════════════════════════════════════════════════════

public enum ErrorTier: Equatable {
    case silent
    case inline
    case banner
    case fullscreen
}

public struct ErrorPresenter {
    /// 给定 error，决定它该走哪个展示通道。
    public static func tier(for error: Error) -> ErrorTier {
        // 1. Cancellation —— 永远 silent。
        if ErrorLocalizer.isCancellation(error) { return .silent }

        // 2. Auth 失效 —— fullscreen，让上层 SessionManager 触发登录页。
        let raw = error.localizedDescription
        if raw.contains("Auth session") ||
           raw.contains("JWT expired") ||
           raw.localizedCaseInsensitiveContains("not authenticated") ||
           raw.contains("Token has expired") {
            return .fullscreen
        }

        // 3. Validation / 业务规则违例 —— inline。
        //    PostgREST RAISE EXCEPTION 在 Supabase Swift SDK 里通常带
        //    "PGRST" 或自定义 message。我们走启发式：含 "不能为空" /
        //    "必填" / "格式" 视为 inline。这一步保守一点 —— 拿不准
        //    的让它继续走到 banner 是安全的。
        if raw.contains("不能为空") || raw.contains("必填") || raw.contains("格式不正确") {
            return .inline
        }

        // 4. 其它一切 —— banner（默认通道）。
        return .banner
    }

    /// 转换成面向用户的文案；silent tier 返回 nil。
    /// 这是 VM `catch` 块推广 (iter7 §C) 的核心入口：
    /// ```
    /// if let msg = ErrorPresenter.userFacingMessage(error) {
    ///     self.errorMessage = msg
    /// }
    /// ```
    public static func userFacingMessage(_ error: Error) -> String? {
        if ErrorLocalizer.isCancellation(error) { return nil }
        return ErrorLocalizer.localize(error)
    }

    /// VM 端最常用的便捷方法：返回 `(tier, message)`，message 为 nil
    /// 时表示 silent，调用方应直接 return 不赋值 errorMessage。
    public static func present(_ error: Error) -> (tier: ErrorTier, message: String?) {
        let t = tier(for: error)
        if t == .silent { return (.silent, nil) }
        return (t, ErrorLocalizer.localize(error))
    }

    /// fullscreen tier 判定 —— View 层用它决定要不要弹"重新登录"模态。
    public static func isFullscreen(_ error: Error) -> Bool {
        return tier(for: error) == .fullscreen
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - ErrorFullscreenView (auth-required modal)
// ══════════════════════════════════════════════════════════════════

/// fullscreen tier 错误的标准 modal：标题 + 文案 + 重新登录按钮。
/// 上层用 `.errorFullscreen($vm.fullscreenError, signOut: { ... })`
/// 把 VM 的 fullscreen error 投到这个 modal。
public struct ErrorFullscreenView: View {
    let message: String
    let onReauthenticate: () -> Void
    let onDismiss: () -> Void

    public init(
        message: String,
        onReauthenticate: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.onReauthenticate = onReauthenticate
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: BsSpacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(BsColor.brandAzure)
                .padding(.top, BsSpacing.xl)

            Text("登录已过期")
                .font(BsTypography.sectionTitle)
                .foregroundStyle(BsColor.ink)

            Text(message)
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BsSpacing.xl)

            Spacer()

            VStack(spacing: BsSpacing.sm) {
                Button {
                    onReauthenticate()
                } label: {
                    Text("重新登录")
                        .font(BsTypography.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BsSpacing.md)
                        .background(BsColor.brandAzure)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("取消") {
                    onDismiss()
                }
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
            }
            .padding(.horizontal, BsSpacing.xl)
            .padding(.bottom, BsSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BsColor.pageBackground.ignoresSafeArea())
    }
}

public extension View {
    /// VM 暴露 `@Published var fullscreenError: String?`，View 在 root
    /// 上挂 `.errorFullscreen($vm.fullscreenError) { signOut() }` 即可。
    func errorFullscreen(
        _ message: Binding<String?>,
        onReauthenticate: @escaping () -> Void
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
        return self.fullScreenCover(isPresented: isPresented) {
            ErrorFullscreenView(
                message: message.wrappedValue ?? "登录已过期，请重新登录",
                onReauthenticate: {
                    message.wrappedValue = nil
                    onReauthenticate()
                },
                onDismiss: {
                    message.wrappedValue = nil
                }
            )
        }
    }
}
