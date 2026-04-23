import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.4d — Settings → 通知偏好 ViewModel
//
// Mirrors Web `src/app/dashboard/settings/notifications/page.tsx` +
// `src/lib/actions/settings.ts` (fetchSettings / updateSettings /
// fetchNotificationPrefs / updateNotificationPrefs).
//
// Three persisted groups:
//   1. Channels — `user_settings.push_notifications` + `email_notifications`
//   2. Types   — `user_settings.notification_prefs.types`   (JSONB, 050a)
//   3. Quiet   — `user_settings.notification_prefs.quiet_hours`
//
// Persistence = single UPSERT on `user_settings` with onConflict=user_id,
// matching Web which does one upsert per group but onto the same row.
// We combine into a single upsert for fewer round-trips (and the row
// has a UNIQUE (user_id) constraint so it's safe).
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class SettingsNotificationsViewModel: ObservableObject {
    // MARK: - Channel toggles (user_settings columns)
    @Published public var pushNotifications: Bool = true
    @Published public var emailNotifications: Bool = true

    // MARK: - Type toggles + quiet hours (JSONB)
    @Published public var preferences: NotificationPreferences = .default

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

    /// Load channels + JSONB prefs from `user_settings`. When the row
    /// is missing we fall back to `NotificationPreferences.default`
    /// (Web does the same in `fetchSettings` + `fetchNotificationPrefs`).
    public func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let userId = session.user.id

            struct Row: Decodable {
                let pushNotifications: Bool?
                let emailNotifications: Bool?
                // Kept as AnyJSON so we can tolerantly merge into defaults.
                let notificationPrefs: AnyJSON?

                enum CodingKeys: String, CodingKey {
                    case pushNotifications = "push_notifications"
                    case emailNotifications = "email_notifications"
                    case notificationPrefs = "notification_prefs"
                }
            }

            let rows: [Row] = try await client
                .from("user_settings")
                .select("push_notifications, email_notifications, notification_prefs")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            if let row = rows.first {
                self.pushNotifications = row.pushNotifications ?? true
                self.emailNotifications = row.emailNotifications ?? true
                self.preferences = NotificationPreferences.merge(
                    raw: Self.dictionary(from: row.notificationPrefs)
                )
            } else {
                // No row yet → fall through to defaults (matches Web).
                self.pushNotifications = true
                self.emailNotifications = true
                self.preferences = .default
            }
        } catch {
            self.errorMessage = "加载通知偏好失败：\(ErrorLocalizer.localize(error))"
        }

        isLoading = false
    }

    // MARK: - Save

    /// UPSERT the full row on `user_settings` with onConflict=user_id.
    /// Matches Web behavior (settings.ts upsert calls) while reducing
    /// the three Web calls to a single round-trip.
    public func save() async {
        isSaving = true
        errorMessage = nil
        savedSuccessfully = false

        do {
            let session = try await client.auth.session
            let userId = session.user.id

            let payload = SettingsUpsertPayload(
                userId: userId.uuidString,
                pushNotifications: pushNotifications,
                emailNotifications: emailNotifications,
                notificationPrefs: preferences
            )

            try await client
                .from("user_settings")
                .upsert(payload, onConflict: "user_id")
                .execute()

            savedSuccessfully = true
        } catch {
            self.errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
        }

        isSaving = false
    }

    // MARK: - Helpers

    /// Convert Supabase `AnyJSON` into a plain dictionary for
    /// `NotificationPreferences.merge(raw:)` without depending on the
    /// SDK's internal case semantics.
    private static func dictionary(from json: AnyJSON?) -> [String: Any]? {
        guard let json else { return nil }
        guard let data = try? JSONEncoder().encode(json),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        return dict
    }
}

// MARK: - Upsert payload

/// Codable payload matching `user_settings` columns exposed by Web.
/// `notification_prefs` is sent as a nested object (JSONB on Postgres).
private struct SettingsUpsertPayload: Encodable {
    let userId: String
    let pushNotifications: Bool
    let emailNotifications: Bool
    let notificationPrefs: NotificationPreferences

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pushNotifications = "push_notifications"
        case emailNotifications = "email_notifications"
        case notificationPrefs = "notification_prefs"
    }
}
