import Foundation

// ══════════════════════════════════════════════════════════════════
// Batch C.4d — NotificationPreferences
//
// 1:1 mirror of Web `src/lib/notifications/prefs.ts` — the canonical
// shape stored in `user_settings.notification_prefs` (JSONB, migration
// 050a_notification_prefs.sql).
//
// Structure:
//   {
//     types: { mention, approval, task, broadcast, attendance: Bool },
//     quiet_hours: { enabled: Bool, start: "HH:MM", end: "HH:MM" }
//   }
//
// When the DB returns `{}` or missing fields, `merge(raw:)` falls back
// to `default` — matching Web `mergePrefs()`. Safe to serialise back
// through Supabase Swift SDK via `Codable` / `AnyJSON`.
// ══════════════════════════════════════════════════════════════════

public enum NotificationTypeKey: String, CaseIterable, Codable, Hashable {
    case mention
    case approval
    case task
    case broadcast
    case attendance
}

public struct NotificationTypePrefs: Codable, Hashable {
    public var mention: Bool
    public var approval: Bool
    public var task: Bool
    public var broadcast: Bool
    public var attendance: Bool

    public init(
        mention: Bool = true,
        approval: Bool = true,
        task: Bool = true,
        broadcast: Bool = true,
        attendance: Bool = true
    ) {
        self.mention = mention
        self.approval = approval
        self.task = task
        self.broadcast = broadcast
        self.attendance = attendance
    }

    public subscript(key: NotificationTypeKey) -> Bool {
        get {
            switch key {
            case .mention: return mention
            case .approval: return approval
            case .task: return task
            case .broadcast: return broadcast
            case .attendance: return attendance
            }
        }
        set {
            switch key {
            case .mention: mention = newValue
            case .approval: approval = newValue
            case .task: task = newValue
            case .broadcast: broadcast = newValue
            case .attendance: attendance = newValue
            }
        }
    }
}

public struct QuietHours: Codable, Hashable {
    public var enabled: Bool
    /// "HH:MM" 24h, local time (matches Web string format)
    public var start: String
    public var end: String

    public init(enabled: Bool = false, start: String = "22:00", end: String = "08:00") {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case start
        case end
    }
}

public struct NotificationPreferences: Codable, Hashable {
    public var types: NotificationTypePrefs
    public var quietHours: QuietHours

    public init(
        types: NotificationTypePrefs = NotificationTypePrefs(),
        quietHours: QuietHours = QuietHours()
    ) {
        self.types = types
        self.quietHours = quietHours
    }

    enum CodingKeys: String, CodingKey {
        case types
        case quietHours = "quiet_hours"
    }

    public static let `default` = NotificationPreferences()

    // MARK: - Tolerant merge (mirrors Web `mergePrefs`)

    /// Merge a raw JSON dictionary (as decoded from `user_settings.notification_prefs`)
    /// into a fully-populated `NotificationPreferences`, falling back to `default`
    /// for missing/invalid fields. Matches Web `mergePrefs()` semantics so iOS
    /// never crashes on empty/partial rows.
    public static func merge(raw: [String: Any]?) -> NotificationPreferences {
        var result = NotificationPreferences.default
        guard let raw else { return result }

        if let typesRaw = raw["types"] as? [String: Any] {
            for key in NotificationTypeKey.allCases {
                if let v = typesRaw[key.rawValue] as? Bool {
                    result.types[key] = v
                }
            }
        }

        if let quietRaw = raw["quiet_hours"] as? [String: Any] {
            if let enabled = quietRaw["enabled"] as? Bool {
                result.quietHours.enabled = enabled
            }
            if let start = quietRaw["start"] as? String,
               NotificationPreferences.isValidHHMM(start) {
                result.quietHours.start = start
            }
            if let end = quietRaw["end"] as? String,
               NotificationPreferences.isValidHHMM(end) {
                result.quietHours.end = end
            }
        }

        return result
    }

    /// Validates "HH:MM" 24h format. Matches Web `normalizeTime` regex.
    public static func isValidHHMM(_ s: String) -> Bool {
        let pattern = #"^([01]\d|2[0-3]):([0-5]\d)$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
