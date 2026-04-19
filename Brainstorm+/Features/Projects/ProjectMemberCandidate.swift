import Foundation

// MARK: - 1.9 Member picker DTO
//
// Narrow shape for the member picker. Mirrors Web `fetchAllUsersForPicker()` in
// `BrainStorm+-Web/src/lib/actions/projects.ts`, which selects:
//
// ```ts
// adminDb
//   .from('profiles')
//   .select('id, full_name, avatar_url, role, department')
//   .eq('status', 'active')
//   .order('full_name')
// ```
//
// We deliberately do NOT reuse the core `Profile` model because:
// 1. `Profile` decodes many more columns than the picker needs; a narrow DTO keeps the
//    select list tight and avoids decoder failures when a sparse row is returned.
// 2. Keeping this DTO local to the Projects feature preserves the "one fetch, one shape"
//    pattern established by `ProjectOwnerSummary` in 1.7.
public struct ProjectMemberCandidate: Identifiable, Codable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?
    public let role: String?
    public let department: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case role
        case department
    }

    /// Display-safe name — prefers `full_name`, falls back to the short UUID prefix so
    /// the picker row never renders a completely unlabeled line.
    public var displayName: String {
        if let name = fullName, !name.isEmpty { return name }
        return String(id.uuidString.prefix(8))
    }
}
