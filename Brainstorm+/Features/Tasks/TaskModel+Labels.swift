import SwiftUI

/// CN label + color helpers for TaskModel enums.
///
/// Kept in the Tasks feature folder (not Core/Models) because Core is
/// owned by B.4's scope and this is purely presentational. Mirrors Web's
/// `STATUS_COLUMNS` / `PRIORITY_MAP` dicts in
/// `BrainStorm+-Web/src/app/dashboard/tasks/page.tsx:22-34`.
extension TaskModel.TaskStatus {
    /// Chinese label shown in the UI (matches Web 1:1).
    public var cnLabel: String {
        switch self {
        case .todo: return "待办"
        case .inProgress: return "进行中"
        case .review: return "审核中"
        case .done: return "已完成"
        }
    }

    /// Column dot / tag tint. Mirrors Web's tailwind class intent
    /// (gray / blue / amber / emerald).
    public var tint: Color {
        switch self {
        case .todo: return BsColor.inkMuted
        case .inProgress: return BsColor.brandAzure
        case .review: return BsColor.warning
        case .done: return BsColor.success
        }
    }
}

extension TaskModel.TaskPriority {
    public var cnLabel: String {
        switch self {
        case .urgent: return "紧急"
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    public var tint: Color {
        switch self {
        case .urgent: return BsColor.brandCoral
        case .high: return BsColor.warning
        case .medium: return BsColor.brandAzure
        case .low: return BsColor.inkMuted
        }
    }
}
