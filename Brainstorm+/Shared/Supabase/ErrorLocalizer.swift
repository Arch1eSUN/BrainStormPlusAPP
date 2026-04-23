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
// 真实错误信息，宁可英文也好过模糊"未知错误"）。
// ══════════════════════════════════════════════════════════════════

public enum ErrorLocalizer {
    /// 精确匹配优先，命中则返回对应中文。
    private static let exactMap: [String: String] = [
        // Supabase Auth
        "Auth session missing.":        "登录已失效，请重新登录",
        "Auth session missing!":        "登录已失效，请重新登录",
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

        // URLSession / 网络
        "The Internet connection appears to be offline.": "当前无网络连接",
        "The network connection was lost.":               "网络连接中断，请重试",
        "A server with the specified hostname could not be found.": "无法连接服务器，请检查网络",
        "The request timed out.":                         "请求超时，请重试",
        "cancelled":                                      "请求已取消",

        // PostgREST / RLS
        "permission denied":             "权限不足",
        "new row violates row-level security policy":       "无权执行此操作",
        "duplicate key value violates unique constraint":   "数据冲突：已存在相同记录",
        "foreign key violation":          "数据关联错误",
    ]

    /// 关键词 fallback —— 包含这些子串时返回对应中文。
    private static let keywordMap: [(needle: String, zh: String)] = [
        ("Auth session",        "登录已失效，请重新登录"),
        ("session_not_found",   "登录已失效，请重新登录"),
        ("JWT",                 "登录已过期，请重新登录"),
        ("not authenticated",   "请先登录"),
        ("row-level security",  "无权执行此操作"),
        ("permission denied",   "权限不足"),
        ("network",             "网络异常，请稍后再试"),
        ("Network",             "网络异常，请稍后再试"),
        ("offline",             "当前无网络连接"),
        ("timed out",           "请求超时，请重试"),
        ("timeout",             "请求超时，请重试"),
        ("Not Found",           "资源不存在"),
        ("could not be found",  "资源不存在"),
        ("duplicate key",       "数据冲突：已存在相同记录"),
        ("conflict",            "数据冲突"),
        ("foreign key",         "数据关联错误"),
    ]

    /// 把任意 Error 映射成面向用户的中文 errorMessage。
    public static func localize(_ error: Error) -> String {
        let raw = error.localizedDescription

        // 1. 精确匹配
        if let zh = exactMap[raw] { return zh }

        // 2. 去掉尾部标点再试一次
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".!? \n"))
        if let zh = exactMap[trimmed] { return zh }

        // 3. 关键词 fallback
        for entry in keywordMap where raw.localizedCaseInsensitiveContains(entry.needle) {
            return entry.zh
        }

        // 4. 透传原文（最后兜底，不隐藏真实错误）
        return raw
    }
}
