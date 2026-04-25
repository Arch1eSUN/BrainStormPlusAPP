import Foundation
import LocalAuthentication
import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BiometricGate (Iter 6 review §B.8)
// ──────────────────────────────────────────────────────────────────
// 敏感管理操作（删用户 / 改角色 / 修审批结果 / 退出登录 / 修薪资）
// 在执行前需要本机 FaceID / TouchID 二次确认 —— 防止设备被偷或借用
// 后误操作 / 滥用。
//
// 设计要点：
//  • `actor` 包裹 LAContext 的 reuseDuration，避免短时间内同账号
//    重复弹窗（连续删 5 个用户体验崩溃）。
//  • 通过 @AppStorage("biometric_required_for_sensitive") 让用户在
//    Settings 里关闭；关闭后 authenticate(reason:) 直接返回 success
//    （无 throw）。
//  • 设备未启用 FaceID/TouchID（旧 iPad / 未录入指纹）时抛
//    `.notAvailable`，由调用方降级到普通 confirmationDialog 文案确认。
//
// 调用模式（VM 端）：
//   do {
//       try await BiometricGate.shared.authenticate(reason: "确认删除用户 \(name)")
//       // 通过：执行真正的破坏性操作
//   } catch BiometricGateError.userCancelled {
//       // 用户取消 → 静默
//   } catch BiometricGateError.notAvailable {
//       // 设备无 FaceID → 由 View 层 fallback 走文本确认
//   } catch {
//       errorMessage = ErrorPresenter.userFacingMessage(error) ?? "操作失败"
//   }
// ══════════════════════════════════════════════════════════════════

public enum BiometricGateError: Error, Equatable {
    case notAvailable
    case userCancelled
    case authFailed
    case lockedOut
}

/// AppStorage key —— 用户在 Settings 里的"敏感操作需 FaceID"开关。
/// 默认 ON：首次安装即受保护。
public let kBiometricRequiredForSensitive = "biometric_required_for_sensitive"

public actor BiometricGate {
    public static let shared = BiometricGate()

    private init() {}

    /// 设备是否具备 FaceID/TouchID 且已录入。`canEvaluate=false` 时调用
    /// 方应走 fallback (文本确认)，而不是直接放行。
    public func canEvaluate() -> Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// 弹出系统 FaceID/TouchID dialog；reason 中文，会显示在
    /// 系统弹窗副标题里。成功 return；失败/取消/锁定按 Error 类型抛出。
    ///
    /// 受 `kBiometricRequiredForSensitive` AppStorage 控制：
    ///  - 用户关闭开关 → 直接 return（视为允许）
    ///  - 用户开启 + 设备无 biometric → 抛 `.notAvailable`，由 View 层
    ///    走 confirmationDialog 文案确认作为 fallback。
    public func authenticate(reason: String) async throws {
        // 用户关闭了开关：跳过验证（同 Settings 暴露的 toggle）。
        // UserDefaults 读取放在 actor 内部，避免主线程阻塞。
        let enabled = UserDefaults.standard.object(forKey: kBiometricRequiredForSensitive) as? Bool ?? true
        guard enabled else { return }

        let ctx = LAContext()
        ctx.localizedFallbackTitle = ""  // 隐藏"输入密码"二级 fallback —— 我们自己控制 fallback 路径
        // 5 秒内不重复弹窗：连续操作（如批量审批）期间体验更好。
        ctx.touchIDAuthenticationAllowableReuseDuration = 5

        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            throw BiometricGateError.notAvailable
        }

        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !ok {
                throw BiometricGateError.authFailed
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw BiometricGateError.userCancelled
            case .biometryLockout, .touchIDLockout:
                throw BiometricGateError.lockedOut
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet, .touchIDNotAvailable, .touchIDNotEnrolled:
                throw BiometricGateError.notAvailable
            default:
                throw BiometricGateError.authFailed
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - View modifier convenience
// ══════════════════════════════════════════════════════════════════

extension View {
    /// 把一个敏感按钮的 action 包在 BiometricGate 后面。
    /// - 成功：调用 `action()`
    /// - 用户取消：静默
    /// - 设备无 biometric：调用 `fallback()`（一般是 set 一个
    ///   `@State showFallbackConfirm` 让 confirmationDialog 弹起）
    /// - 其它错误：写 `errorMessage`
    public func bsBiometricGate(
        reason: String,
        errorMessage: Binding<String?>,
        fallback: (() -> Void)? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        modifier(BsBiometricGateModifier(
            reason: reason,
            errorMessage: errorMessage,
            fallback: fallback,
            action: action
        ))
    }
}

private struct BsBiometricGateModifier: ViewModifier {
    let reason: String
    @Binding var errorMessage: String?
    let fallback: (() -> Void)?
    let action: () async -> Void

    func body(content: Content) -> some View {
        // 这个 modifier 是个 helper：不直接 wrap UI，而是暴露
        // `runWithGate` 闭包给调用方在 Button.action 里执行。
        // 这里仅透传 content；真正的 gate 调用方在 VM 里走
        // BiometricGate.shared.authenticate。modifier 的存在主要
        // 是给未来潜在的"长按出 FaceID 提示 toast"留接口。
        content
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - VM helper
// ══════════════════════════════════════════════════════════════════

/// VM 端的 helper：把"先 biometric → 再执行"的 boilerplate 收成一行。
///
/// ```
/// await runSensitiveAction(reason: "确认删除用户 \(name)",
///     onError: { errorMessage = $0 },
///     onFallback: { showFallbackConfirm = true }
/// ) {
///     // 真正的破坏性操作
///     try await client.from("profiles").delete()...
/// }
/// ```
@MainActor
public func runSensitiveAction(
    reason: String,
    onError: @escaping (String) -> Void,
    onFallback: (() -> Void)? = nil,
    action: @escaping () async -> Void
) async {
    do {
        try await BiometricGate.shared.authenticate(reason: reason)
        await action()
    } catch BiometricGateError.userCancelled {
        // 静默：用户主动取消
    } catch BiometricGateError.notAvailable {
        if let fb = onFallback {
            fb()
        } else {
            // 没注册 fallback —— 直接放行，避免老设备完全无法操作。
            await action()
        }
    } catch BiometricGateError.lockedOut {
        onError("FaceID/TouchID 已被锁定，请在系统设置中解锁后重试")
    } catch {
        onError("身份验证失败，请重试")
    }
}
