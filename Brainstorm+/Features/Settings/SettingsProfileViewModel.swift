import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.4d — Settings → 个人资料 ViewModel
//
// Mirrors Web `src/lib/actions/settings.ts` — `fetchProfile()` +
// `updateProfile({ full_name, display_name, phone, department, position })`.
//
// Web's `updateProfile` gates on `superadmin` OR `hr_ops` capability
// ("仅 Super Admin 或 HR Ops 可修改员工个人信息"). We mirror that gate
// client-side via `RBACManager` so the form disables itself for
// non-privileged users before the server RLS also rejects the write.
//
// Avatar upload is NOT exposed by Web's settings page — `profiles.avatar_url`
// exists in schema but the Web UI does not offer an upload control here.
// Staying 1:1, iOS also omits avatar upload (read-only display only).
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class SettingsProfileViewModel: ObservableObject {
    // MARK: - Form fields (bound by view)
    @Published public var fullName: String = ""
    @Published public var displayName: String = ""
    @Published public var phone: String = ""
    @Published public var department: String = ""
    @Published public var position: String = ""

    // MARK: - Read-only display
    @Published public private(set) var email: String?
    @Published public private(set) var avatarUrl: String?
    @Published public private(set) var role: String?

    // MARK: - Permissions (mirrors Web `canEditProfile`)
    @Published public private(set) var canEditProfile: Bool = false

    // MARK: - UI state
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public var savedSuccessfully: Bool = false

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    // MARK: - Load

    public func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let userId = session.user.id

            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            self.fullName = profile.fullName ?? ""
            self.displayName = profile.displayName ?? ""
            self.phone = profile.phone ?? ""
            self.department = profile.department ?? ""
            self.position = profile.position ?? ""
            self.email = profile.email
            self.avatarUrl = profile.avatarUrl
            self.role = profile.role
            self.canEditProfile = Self.resolveCanEditProfile(profile: profile)
        } catch {
            self.errorMessage = "加载个人资料失败：\(ErrorLocalizer.localize(error))"
        }

        isLoading = false
    }

    // MARK: - Save

    public func save() async {
        guard canEditProfile else {
            errorMessage = "权限不足：仅 Super Admin 或 HR Ops 可修改员工个人信息"
            return
        }

        isSaving = true
        errorMessage = nil
        savedSuccessfully = false

        do {
            let session = try await client.auth.session
            let userId = session.user.id

            let payload = ProfileUpdatePayload(
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: emptyToNil(displayName),
                phone: emptyToNil(phone),
                department: emptyToNil(department),
                position: emptyToNil(position)
            )

            try await client
                .from("profiles")
                .update(payload)
                .eq("id", value: userId)
                .execute()

            savedSuccessfully = true
        } catch {
            self.errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
        }

        isSaving = false
    }

    // MARK: - Helpers

    private func emptyToNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Mirror of Web `canEditProfile = primaryRole === 'superadmin' || hasCapability(caps, 'hr_ops')`.
    private static func resolveCanEditProfile(profile: Profile) -> Bool {
        let migration = RBACManager.shared.migrateLegacyRole(profile.role)
        if migration.primaryRole == .superadmin {
            return true
        }
        let effective = RBACManager.shared.getEffectiveCapabilities(for: profile)
        return effective.contains(.hr_ops)
    }
}

// MARK: - Update payload

/// Codable payload matching `profiles` columns edited by Web's
/// settings page. Nil values are omitted from the JSON so we don't
/// accidentally clear columns the user didn't touch — Supabase Swift
/// SDK does this automatically for `Optional` values via synthesized
/// `encode(to:)`.
private struct ProfileUpdatePayload: Encodable {
    let fullName: String
    let displayName: String?
    let phone: String?
    let department: String?
    let position: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case displayName = "display_name"
        case phone
        case department
        case position
    }
}
