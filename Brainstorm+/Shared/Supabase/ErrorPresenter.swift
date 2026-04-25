import Foundation

// ══════════════════════════════════════════════════════════════════
// ErrorPresenter — 错误展示分级 (iter6 §B.2)
//
// 把 raw Error 映射成一个 ErrorTier + 一段面向用户的中文文案。
// VM 层根据 tier 决定 UI 通道：
//   • silent     — 不展示（CancellationError、retry 可恢复）
//   • inline     — 表单字段旁的小红字
//   • banner     — 顶部 toast / .zyErrorBanner（默认通道）
//   • fullscreen — modal（auth required / 关键流程被打断）
//
// 渐进迁移策略：先在 TeamAttendanceVM / ApprovalQueueVM / ChatRoomVM
// 三个高频 VM 落地。其余 VM 仍用 ErrorLocalizer.localize；后续 iter
// 再统一替换。这一层薄到不引入额外抽象 —— 所有判定都基于已有的
// ErrorLocalizer.isCancellation + URLError / NSError 类型化短路。
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
}
