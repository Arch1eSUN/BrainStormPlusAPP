import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// ApnsTokenSyncer — 把 APNS device token 同步到 Supabase
// ------------------------------------------------------------------
// 流程:
//   1. AppDelegate didRegisterForRemoteNotificationsWithDeviceToken 拿到 Data
//   2. hex 编码后调本 actor 的 upload(token:)
//   3. 写 apns_device_tokens 表 (RLS: user_id = auth.uid())
//      onConflict device_token —— 同 token 换用户也能 upsert，刷 last_used_at
//
// 容错: session/upsert 任意一步失败都 swallow 错误（push 不可用不该
// 阻塞业务），仅 console 留痕，方便用户在 Xcode log 里看到原因。
// ══════════════════════════════════════════════════════════════════

actor ApnsTokenSyncer {
    static let shared = ApnsTokenSyncer()

    private init() {}

    func upload(token: String) async {
        do {
            let userId = try await supabase.auth.session.user.id
            let payload = ApnsTokenUpsertRow(
                userId: userId.uuidString,
                deviceToken: token,
                bundleId: Bundle.main.bundleIdentifier ?? "com.samuraiplus.brainstormplus",
                platform: "ios"
            )
            try await supabase
                .from("apns_device_tokens")
                .upsert(payload, onConflict: "device_token")
                .execute()
            print("[APNS] token uploaded:", token.prefix(8), "…")
        } catch {
            print("[APNS] token upload failed:", error)
        }
    }
}

private struct ApnsTokenUpsertRow: Encodable {
    let userId: String
    let deviceToken: String
    let bundleId: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case deviceToken = "device_token"
        case bundleId = "bundle_id"
        case platform
    }
}
