import Foundation
import Supabase

@Observable
public final class SettingsViewModel {
    public var profile: Profile?
    public var isLoading = false
    /// True 当 profile 仍是从 cache 命中的旧值、网络请求尚未返回。
    /// 视图层据此把内容标 redacted（shimmer 占位），刷新到货后撤掉。
    public var isStale = false
    public var errorMessage: String?

    @MainActor
    public func loadProfile() async {
        // 1) Cache-first —— 先用本地缓存填一帧，避免白屏。
        do {
            let session = try await supabase.auth.session
            let uid = session.user.id
            if let cached = ProfileCache.load(userId: uid) {
                self.profile = cached
                self.isStale = true
            }
        } catch {
            // 取不到 session 就直接走 fetch path（多半会再失败一次然后 banner）
        }

        isLoading = true
        errorMessage = nil

        do {
            let session = try await supabase.auth.session
            let currentUser = session.user

            let fetchedProfile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: currentUser.id)
                .single()
                .execute()
                .value

            self.profile = fetchedProfile
            self.isStale = false
            ProfileCache.save(fetchedProfile)
        } catch {
            // Cancellation 静默 —— view 切换 / 重 task 时会 cancel 旧 fetch。
            if ErrorLocalizer.isCancellation(error) {
                isLoading = false
                return
            }
            // 如果 cache 已经填上了，就不要再覆盖一个 banner —— stale 数据
            // 比一段红字更友好。banner 只在彻底没 profile 时显示。
            if profile == nil {
                self.errorMessage = "加载个人资料失败：\(ErrorLocalizer.localize(error))"
            }
        }

        isLoading = false
    }

    @MainActor
    public func signOut(sessionManager: SessionManager) async {
        do {
            try await sessionManager.logout()
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
