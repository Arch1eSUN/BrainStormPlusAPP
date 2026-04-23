import Foundation
import SwiftUI

/// Mirrors Web `daily_work_state` row. Replaces legacy `schedules` table.
/// See `BrainStorm+-Web/src/app/dashboard/schedules/_hooks/use-schedule-data.ts`.
public struct DailyWorkState: Codable, Hashable {
    public let userId: UUID
    public let workDate: String          // "YYYY-MM-DD"
    public let state: String             // DB enum (normal / business_trip / ...)
    public let source: String?           // "system" | "manager_override" | "approved_request" | ...
    public let isPaid: Bool?
    public let isWorkDay: Bool?
    public let expectedStart: String?    // "HH:MM:SS" from TIME column
    public let expectedEnd: String?
    public let flexibleHours: Bool?
    /// Concrete leave-type slug when state == "personal_leave" — drives the label.
    public let leaveType: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case workDate = "work_date"
        case state
        case source
        case isPaid = "is_paid"
        case isWorkDay = "is_work_day"
        case expectedStart = "expected_start"
        case expectedEnd = "expected_end"
        case flexibleHours = "flexible_hours"
        case leaveType = "leave_type"
    }
}

// MARK: - Labels (mirrors Web _lib/colors.ts)

public enum WorkStateLabels {
    /// DB state enum → Chinese short label.
    public static let state: [String: String] = [
        "normal": "排班",
        "business_trip": "出差",
        "field_work": "外勤",
        "comp_time": "调休",
        "personal_leave": "事假",
        "public_holiday": "法定假",
        "weekend_rest": "休息",
        "absent": "旷工",
        "pending": "待定",
    ]

    /// `personal_leave` bucket is a catch-all; concrete leave_type picks the real label.
    public static let leaveType: [String: String] = [
        "personal": "事假",
        "sick": "病假",
        "annual": "年假",
        "marriage": "婚假",
        "bereavement": "丧假",
        "funeral": "丧假",
        "maternity": "产假",
        "paternity": "陪产假",
        "comp_time": "调休",
    ]

    /// Short label — follows Web `getLabelByState`.
    public static func label(state: String?, leaveType: String? = nil) -> String {
        guard let state else { return "—" }
        if state == "personal_leave", let lt = leaveType, let mapped = Self.leaveType[lt] {
            return mapped
        }
        return Self.state[state] ?? state
    }
}

// MARK: - Colors (mirrors Web _lib/colors.ts `getColorByState`)

public enum WorkStateColors {
    public static func color(state: String?, expectedStart: String? = nil) -> Color {
        guard let state else { return Color(hex: "#e5e7eb") }
        switch state {
        case "normal":
            if let hourStr = expectedStart?.prefix(2), let hour = Int(hourStr) {
                if hour < 10 { return Color(hex: "#10b981") } // morning
                if hour < 15 { return Color(hex: "#3b82f6") } // mid
                return Color(hex: "#8b5cf6")                   // evening
            }
            return Color(hex: "#3b82f6")
        case "business_trip":   return Color(hex: "#f59e0b")
        case "field_work":      return Color(hex: "#f97316")
        case "comp_time":       return Color(hex: "#94a3b8")
        case "personal_leave":  return Color(hex: "#6b7280")
        case "public_holiday":  return Color(hex: "#ef4444")
        case "absent":          return Color(hex: "#dc2626")
        case "weekend_rest",
             "rest":            return Color(hex: "#e5e7eb")
        case "pending":         return Color(hex: "#d1d5db")
        default:                return Color(hex: "#e5e7eb")
        }
    }
}

// MARK: - Source helper

public enum WorkStateSource {
    public static func label(_ source: String?) -> String? {
        switch source {
        case "system":            return "系统排班"
        case "manager_override":  return "管理员排班"
        case "approved_request":  return "已审批"
        case "imported":          return "导入"
        default:                  return nil
        }
    }
}
