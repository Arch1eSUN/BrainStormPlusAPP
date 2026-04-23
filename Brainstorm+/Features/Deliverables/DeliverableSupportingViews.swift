import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverables support: status chip + platform detection.
//
// Kept in its own file so the list + detail views share the chip and
// the link-platform regex table (1:1 port of
// `BrainStorm+-Web/src/app/dashboard/deliverables/page.tsx:23-43`
// without pulling the entire Web file into each SwiftUI view).
// ══════════════════════════════════════════════════════════════════

// MARK: - Status chip

/// Mirrors Web's `STATUS_CFG` color mapping (page.tsx:15-21) on top of
/// the generic `Shared/DesignSystem/Components/StatusChip.swift`.
public struct DeliverableStatusChip: View {
    public let status: Deliverable.DeliverableStatus

    public init(status: Deliverable.DeliverableStatus) {
        self.status = status
    }

    public var body: some View {
        StatusChip(label: status.displayName, tone: tone(for: status))
    }

    private func tone(for status: Deliverable.DeliverableStatus) -> Color {
        switch status {
        case .notStarted, .pending:  return .gray
        case .inProgress:            return .blue
        case .submitted:             return .orange
        case .accepted, .approved:   return .green
        case .revision, .rejected:   return .red
        }
    }
}

// MARK: - Platform detection

/// Label + color for an external link. Regex patterns copied from
/// `LINK_PLATFORMS` in page.tsx:23-36.
public struct DeliverablePlatform {
    public let label: String
    public let color: Color

    private static let table: [(NSRegularExpression, DeliverablePlatform)] = {
        let entries: [(String, String, Color)] = [
            (#"drive\.google\.com"#,      "Google Drive", Color(red: 66/255,  green: 133/255, blue: 244/255)),
            (#"docs\.google\.com"#,       "Google Docs",  Color(red: 66/255,  green: 133/255, blue: 244/255)),
            (#"pan\.baidu\.com"#,         "百度网盘",      Color(red: 6/255,   green: 167/255, blue: 255/255)),
            (#"pan\.quark\.cn"#,          "夸克网盘",      Color(red: 79/255,  green: 70/255,  blue: 229/255)),
            (#"github\.com"#,             "GitHub",       Color(red: 36/255,  green: 41/255,  blue: 47/255)),
            (#"figma\.com"#,              "Figma",        Color(red: 162/255, green: 89/255,  blue: 255/255)),
            (#"notion\.so"#,              "Notion",       .black),
            (#"dropbox\.com"#,            "Dropbox",      Color(red: 0/255,   green: 97/255,  blue: 254/255)),
            (#"onedrive\.live\.com|1drv\.ms"#, "OneDrive", Color(red: 0/255,  green: 120/255, blue: 212/255)),
            (#"weiyun\.com"#,             "微云",         Color(red: 0/255,   green: 102/255, blue: 255/255)),
            (#"aliyundrive\.com|alipan\.com"#, "阿里云盘", Color(red: 255/255, green: 106/255, blue: 0/255)),
            (#"lanzoui?\.com"#,           "蓝奏云",       Color(red: 0/255,   green: 153/255, blue: 255/255)),
        ]
        return entries.compactMap { pat, label, color in
            guard let re = try? NSRegularExpression(
                pattern: pat,
                options: [.caseInsensitive]
            ) else { return nil }
            return (re, DeliverablePlatform(label: label, color: color))
        }
    }()

    public static func detect(_ url: String) -> DeliverablePlatform? {
        let range = NSRange(url.startIndex..., in: url)
        for (re, platform) in table {
            if re.firstMatch(in: url, options: [], range: range) != nil {
                return platform
            }
        }
        return DeliverablePlatform(label: "链接", color: .gray)
    }
}
