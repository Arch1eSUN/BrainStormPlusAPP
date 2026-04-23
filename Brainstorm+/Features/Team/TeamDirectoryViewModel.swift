import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 3 — Team directory VM.
//
// Parity target: Web `fetchTeamMembers` + `fetchDepartments`
// (src/lib/actions/team.ts:49-140). iOS differences:
//   - Web pulls email from auth.users via admin client. iOS runs with
//     user JWT; `profiles` does NOT store email (migrations 001/002
//     only add phone + position + department). We surface email only
//     for self on the detail screen via `supabase.auth.session.user.email`.
//   - Server-side scope filter (`scopeFilter`) is enforced by RLS
//     policies; iOS just reads and RLS returns what the viewer can see.
//   - Search is applied client-side — mirrors Web's post-fetch filter
//     (team.ts:103-111). No debounce; `.searchable` publishes on each
//     keystroke which is cheap for small member counts.
// ══════════════════════════════════════════════════════════════════

public struct TeamMember: Decodable, Identifiable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?
    public let role: String?
    public let department: String?
    public let position: String?
    public let phone: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case role
        case department
        case position
        case phone
        case status
    }
}

public struct TeamDepartment: Decodable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
}

@MainActor
public final class TeamDirectoryViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var departmentFilter: String = ""
    @Published public private(set) var allMembers: [TeamMember] = []
    @Published public private(set) var departments: [TeamDepartment] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    @Published public private(set) var viewerCapabilities: [Capability] = []
    @Published public private(set) var viewerPrimaryRole: PrimaryRole = .employee

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    public var canViewDetails: Bool {
        viewerCapabilities.contains(.hr_ops)
            || viewerPrimaryRole == .admin
            || viewerPrimaryRole == .superadmin
    }

    public var filteredMembers: [TeamMember] {
        var rows = allMembers
        if !departmentFilter.isEmpty {
            rows = rows.filter { ($0.department ?? "") == departmentFilter }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { m in
            let haystack = [m.fullName, m.department, m.position, m.phone]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(q)
        }
    }

    public var groupedByDepartment: [(name: String, members: [TeamMember])] {
        let unassigned = "未分配"
        var groups: [String: [TeamMember]] = [:]
        for m in filteredMembers {
            let key: String = {
                if let d = m.department?.trimmingCharacters(in: .whitespaces), !d.isEmpty { return d }
                return unassigned
            }()
            groups[key, default: []].append(m)
        }
        var ordered: [String] = []
        for d in departments where groups[d.name] != nil {
            ordered.append(d.name)
        }
        for k in groups.keys.sorted() where k != unassigned && !ordered.contains(k) {
            ordered.append(k)
        }
        if groups[unassigned] != nil { ordered.append(unassigned) }
        return ordered.map { ($0, groups[$0] ?? []) }
    }

    public func load(sessionProfile: Profile?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let profile = sessionProfile {
            viewerCapabilities = RBACManager.shared.getEffectiveCapabilities(for: profile)
            viewerPrimaryRole = RBACManager.shared.migrateLegacyRole(profile.role).primaryRole
        }

        do {
            async let membersTask = fetchMembers()
            async let deptsTask = fetchDepartments()
            self.allMembers = try await membersTask
            self.departments = (try? await deptsTask) ?? []
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    private func fetchMembers() async throws -> [TeamMember] {
        try await client
            .from("profiles")
            .select("id, full_name, avatar_url, role, department, position, phone, status")
            .order("full_name")
            .execute()
            .value
    }

    private func fetchDepartments() async throws -> [TeamDepartment] {
        try await client
            .from("departments")
            .select("id, name")
            .order("name")
            .execute()
            .value
    }
}
