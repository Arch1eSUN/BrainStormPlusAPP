import Foundation

// ══════════════════════════════════════════════════════════════════
// ProfileCache — 个人资料 stale-while-revalidate 兜底 (iter6 §A.3)
//
// 用户反馈："个人资料那里 进去后也要等一会儿才出现真实信息"。
// 之前 SettingsView / SettingsProfileView 在 .task 里发起请求，
// 网络往返（即便几百毫秒）期间 UI 是空白或 "—"。
//
// 策略：
//   1. 视图 onAppear 同步读取 cache → 先把上次成功的 profile 渲染出
//      来；UI 立即有内容，没有"白屏感"。
//   2. 同时 fire 异步 fetch；返回后写回 cache 并 publish。
//   3. 如果 cache miss（首次登录、清缓存），视图渲染 redacted 占位
//      shimmer，避免文字 "U" / "—" 闪烁。
//
// 存储介质：UserDefaults JSON。Profile 体积小（< 1KB），用 @AppStorage
// 处理 Codable 比较啰嗦，自己写一层 helper 更省心。Key 按 userId
// 分桶，避免账号切换时串味。
// ══════════════════════════════════════════════════════════════════

public enum ProfileCache {
    private static let prefix = "bs.profile.cache.v1."

    private static func key(for userId: UUID) -> String {
        prefix + userId.uuidString
    }

    public static func load(userId: UUID) -> Profile? {
        let k = key(for: userId)
        guard let data = UserDefaults.standard.data(forKey: k) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Profile.self, from: data)
    }

    public static func save(_ profile: Profile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key(for: profile.id))
    }

    public static func clear(userId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }
}
