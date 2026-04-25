import Foundation

// ══════════════════════════════════════════════════════════════════
// ErrorLocalizer — 把 Supabase / URLSession 常见英文 error 映射到中文
//
// 背景：iOS Swift SDK 抛出的 Supabase 错误、NSURLError、Postgres RLS
// 违规等都是英文原文（`Auth session missing.`、`Invalid login…`）。
// 如果直接把 `error.localizedDescription` 塞进 errorMessage banner，
// 用户会看到英文混在中文 UI 里。
//
// 各 ViewModel 的 catch 块应该用：
//   self.errorMessage = ErrorLocalizer.localize(error)
// 而不是直接抄 `error.localizedDescription`。
//
// 精确匹配 + 关键词 fallback 双层；不认识的 key 透传原文（避免掩盖
// 真实错误信息，宁可英文也好过模糊文案）。
//
// Iter 7 §C.3 — 失败文案具象化：
//   • "网络错误" / "请稍后重试" / "权限不足" / "未知错误" 等模糊词
//     全部替换成可执行的具体话术（"下拉刷新或检查 Wi-Fi" 等）。
//   • 401/403/404 通用文案分别映射到 "登录已过期" / "无权操作" /
//     "内容已删除"。
// ══════════════════════════════════════════════════════════════════

public enum ErrorLocalizer {
    // ── Cancellation 检测 ──────────────────────────────────────────
    // iter6 §A.5 — 用户反馈 "the operation could not be completed
    // swift cancellation error 1"。这是 SwiftUI .task 在 view 消失或
    // .onChange 重置时主动 cancel 当前 Task 抛出的 CancellationError。
    // 它属于"框架内部噪声"，不该让用户看见 banner。所有 catch 块都
    // 应该先用 isCancellation 过滤；保留 localize 老接口对历史调用
    // 兼容（cancellation → "请求已取消" 仍会出错时透传），但新增
    // localizeOrNil 给希望直接吞掉 cancellation 的 VM 用。
    public static func isCancellation(_ error: Error) -> Bool {
        if Swift.Task.isCancelled { return true }
        if error is CancellationError { return true }
        if let urlErr = error as? URLError, urlErr.code == .cancelled { return true }
        let ns = error as NSError
        // NSURLErrorCancelled = -999；CancellationError 在某些桥接路径下
        // 以 NSCocoaErrorDomain code 1 / "cancellation" 字面量出现，用户
        // 截图里就是 "swift cancellation error 1"。
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if ns.domain == "Swift.CancellationError" { return true }
        let raw = error.localizedDescription.lowercased()
        if raw.contains("cancellation") || raw.contains("cancelled") || raw.contains("canceled") {
            return true
        }
        return false
    }

    /// Cancellation-aware variant. 返回 nil 时调用方应直接 return,
    /// 不要赋值给 errorMessage —— 这就是"silent tier"的核心实现。
    public static func localizeOrNil(_ error: Error) -> String? {
        if isCancellation(error) { return nil }
        return localize(error)
    }

    /// 精确匹配优先，命中则返回对应中文。
    /// Iter 7 §C.3 — 文案改写要求"具体且可执行"，避免"网络错误 / 请稍后重试"
    /// 一类无法行动的旧文案。
    private static let exactMap: [String: String] = [
        // Supabase Auth
        "Auth session missing.":        "登录已过期，请重新登录",
        "Auth session missing!":        "登录已过期，请重新登录",
        "Invalid login credentials":    "账号或密码错误",
        "Email not confirmed":          "邮箱尚未验证",
        "User already registered":      "该账号已注册",
        "Email rate limit exceeded":    "邮件发送过于频繁，请稍后再试",
        "JWT expired":                  "登录已过期，请重新登录",
        "Token has expired or is invalid": "登录已过期，请重新登录",
        "User not found":               "用户不存在",
        "Unable to validate email address: invalid format": "邮箱格式不正确",
        "Password should be at least 6 characters": "密码至少 6 位",
        "Signup requires a valid password": "请输入有效密码",

        // URLSession / 网络 — 旧文案"网络错误"统一替换成可执行话术。
        "The Internet connection appears to be offline.": "当前无网络连接，请检查 Wi-Fi 或蜂窝数据",
        "The network connection was lost.":               "网络连接不稳定，下拉刷新或检查 Wi-Fi",
        "A server with the specified hostname could not be found.": "无法连接服务器，请检查网络后重试",
        "Could not connect to the server.":               "无法连接服务器，请检查网络后重试",
        "The request timed out.":                         "请求超时，请检查网络后重试",
        "cancelled":                                      "请求已取消",

        // PostgREST / RLS — 旧"权限不足"统一具象化。
        "permission denied":             "你的账号暂无此操作权限，联系管理员开通",
        "new row violates row-level security policy":       "无权操作",
        "duplicate key value violates unique constraint":   "数据冲突：已存在相同记录",
        "foreign key violation":          "数据关联错误",
    ]

    /// 关键词 fallback —— 包含这些子串时返回对应中文。
    /// Iter 7 §C.3 — "网络异常 / 权限不足 / 未知错误" 等词条具象化。
    private static let keywordMap: [(needle: String, zh: String)] = [
        ("Auth session",        "登录已过期，请重新登录"),
        ("session_not_found",   "登录已过期，请重新登录"),
        ("JWT",                 "登录已过期，请重新登录"),
        ("not authenticated",   "登录已过期，请重新登录"),
        ("row-level security",  "无权操作"),
        ("permission denied",   "你的账号暂无此操作权限，联系管理员开通"),
        ("network",             "网络连接不稳定，下拉刷新或检查 Wi-Fi"),
        ("Network",             "网络连接不稳定，下拉刷新或检查 Wi-Fi"),
        ("offline",             "当前无网络连接，请检查 Wi-Fi 或蜂窝数据"),
        ("timed out",           "请求超时，请检查网络后重试"),
        ("timeout",             "请求超时，请检查网络后重试"),
        ("Not Found",           "内容已删除"),
        ("could not be found",  "内容已删除"),
        ("404",                 "内容已删除"),
        ("403",                 "无权操作"),
        ("401",                 "登录已过期，请重新登录"),
        ("duplicate key",       "数据冲突：已存在相同记录"),
        ("conflict",            "数据冲突"),
        ("foreign key",         "数据关联错误"),
        // PostgREST 偶尔抛 generic "server is overloaded" / "rate limit"
        ("rate limit",          "服务暂时繁忙，30 秒后再试"),
        ("overloaded",          "服务暂时繁忙，30 秒后再试"),
    ]

    /// 把任意 Error 映射成面向用户的中文 errorMessage。
    public static func localize(_ error: Error) -> String {
        // 0. URLError 类型化短路 —— iOS 的 localizedDescription 会随系统语言 / 版本
        //    波动（"Could not connect to the server." vs "无法连接到服务器。"），
        //    直接对 .code 分支才稳定。
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet:        return "当前无网络连接，请检查 Wi-Fi 或蜂窝数据"
            case .networkConnectionLost:         return "网络连接不稳定，下拉刷新或检查 Wi-Fi"
            case .timedOut:                      return "请求超时，请检查网络后重试"
            case .cannotFindHost,
                 .dnsLookupFailed:               return "无法连接服务器，请检查网络后重试"
            case .cannotConnectToHost:           return "无法连接服务器，请检查网络后重试"
            case .cancelled:                     return "请求已取消"
            case .secureConnectionFailed,
                 .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot,
                 .clientCertificateRejected,
                 .clientCertificateRequired:     return "安全连接失败，请检查网络环境"
            default:
                break
            }
        }

        // 1. HTTP 状态码短路 —— 对 NSError 里挂 statusCode 的情况做精确分支。
        //    Supabase Swift SDK 把 PostgREST 的 4xx 包成 PostgrestError,
        //    NSError(userInfo: ["statusCode": ...]) —— 我们对常见三个走具象。
        let ns = error as NSError
        if let status = ns.userInfo["statusCode"] as? Int {
            switch status {
            case 401: return "登录已过期，请重新登录"
            case 403: return "无权操作"
            case 404: return "内容已删除"
            case 429: return "服务暂时繁忙，30 秒后再试"
            case 500...599: return "服务暂时繁忙，30 秒后再试"
            default: break
            }
        }

        let raw = error.localizedDescription

        // 2. 精确匹配
        if let zh = exactMap[raw] { return zh }

        // 3. 去掉尾部标点再试一次
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".!? \n"))
        if let zh = exactMap[trimmed] { return zh }

        // 4. 关键词 fallback
        for entry in keywordMap where raw.localizedCaseInsensitiveContains(entry.needle) {
            return entry.zh
        }

        // 5. 透传原文（最后兜底，不隐藏真实错误）
        //    Iter 7 §C.3 — 旧版 fallback "未知错误" 信息密度太低，已替换成
        //    引导性兜底（保留原文供 power user 截图给客服）。
        if raw.isEmpty || raw.count < 3 {
            return "出了点小问题，可在 设置 → 反馈 联系我们"
        }
        return raw
    }
}
