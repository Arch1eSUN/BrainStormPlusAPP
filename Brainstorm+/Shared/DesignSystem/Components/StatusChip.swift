import SwiftUI

/// Capsule-shaped status chip with colored tint background.
///
/// Mirrors the Web `<Badge>` pattern used on the attendance page:
/// - `Capsule().fill(color.opacity(0.15))` background
/// - Color-matched text
/// - Optional leading SF Symbol
///
/// Usage:
/// ```swift
/// StatusChip(label: "准时", tone: .green)
/// StatusChip(label: "外勤", tone: .cyan, icon: "location.fill")
/// ```
public struct StatusChip: View {
    public let label: String
    public let tone: Color
    public let icon: String?
    public let size: Size

    public enum Size {
        case small   // caption2 — used in dense summary cards
        case medium  // caption — standalone status pill
    }

    public init(label: String, tone: Color, icon: String? = nil, size: Size = .small) {
        self.label = label
        self.tone = tone
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: size == .small ? 9 : 11, weight: .semibold))
            }
            Text(label)
                .font(size == .small ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        }
        .padding(.horizontal, size == .small ? 8 : 10)
        .padding(.vertical, size == .small ? 3 : 4)
        .background(Capsule().fill(tone.opacity(0.15)))
        .foregroundStyle(tone)
    }
}

// MARK: - Attendance status convenience

extension StatusChip {
    /// Build a chip from an `attendance.status` string value.
    ///
    /// Schema: `public.attendance.status TEXT CHECK (status IN
    /// ('present','late','absent','half_day','leave','normal','early_leave'))`
    /// — see `004_schema_alignment.sql`. Later code paths (Web
    /// `clock-section.tsx`, reports) also emit `'rest'` and `'field_work'`
    /// via server-side derivation, so this helper handles the full set the
    /// Web UI shows.
    public static func attendance(status: String?) -> StatusChip {
        guard let raw = status, let info = AttendanceStatusMeta.info(for: raw) else {
            return StatusChip(label: "未打卡", tone: .gray)
        }
        return StatusChip(label: info.label, tone: info.tone)
    }
}

/// Static registry of attendance status → label/tone mapping.
/// Kept separate so non-chip views (summary grid, filters) can reuse.
public enum AttendanceStatusMeta {
    public struct Info {
        public let label: String
        public let tone: Color
    }

    public static func info(for raw: String) -> Info? {
        switch raw {
        case "normal", "present": return Info(label: "准时", tone: .green)
        case "late":               return Info(label: "迟到", tone: .orange)
        case "early_leave":        return Info(label: "早退", tone: .yellow)
        case "absent":             return Info(label: "缺勤", tone: .red)
        case "rest":               return Info(label: "休息", tone: .gray)
        case "leave":              return Info(label: "请假", tone: .purple)
        case "field_work":         return Info(label: "外勤", tone: .blue)
        case "half_day":           return Info(label: "半天", tone: .orange)
        default:                   return nil
        }
    }
}
