import Foundation
import Combine
import Supabase

// Parity target: `BrainStorm+-Web/src/app/dashboard/team/[userId]/page.tsx`.
// Web uses the admin client to fetch auth.users email; iOS can't —
// we fall back to `supabase.auth.session.user.email` when viewing self.
// The EvaluationPanel + "发起聊天" button are deferred (see View).
@MainActor
public final class TeamMemberDetailViewModel: ObservableObject {
    @Published public private(set) var profile: Profile?
    @Published public private(set) var selfEmail: String?
    @Published public private(set) var viewerUserId: UUID?
    @Published public private(set) var viewerCapabilities: [Capability] = []
    @Published public private(set) var viewerPrimaryRole: PrimaryRole = .employee
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var accessDenied: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient
    private let userId: UUID

    public init(userId: UUID, client: SupabaseClient = supabase) {
        self.userId = userId
        self.client = client
    }

    public var isSelf: Bool {
        guard let me = viewerUserId else { return false }
        return me == userId
    }

    public var canViewPII: Bool {
        isSelf
            || viewerCapabilities.contains(.hr_ops)
            || viewerPrimaryRole == .admin
            || viewerPrimaryRole == .superadmin
    }

    public func load(sessionProfile: Profile?) async {
        isLoading = true
        errorMessage = nil
        accessDenied = false
        defer { isLoading = false }

        if let session = try? await client.auth.session {
            viewerUserId = session.user.id
            if session.user.id == userId {
                selfEmail = session.user.email
            }
        }

        if let p = sessionProfile {
            viewerCapabilities = RBACManager.shared.getEffectiveCapabilities(for: p)
            viewerPrimaryRole = RBACManager.shared.migrateLegacyRole(p.role).primaryRole
        }

        let hasEvalAccess = viewerCapabilities.contains(.ai_evaluation_access)
            || viewerPrimaryRole == .admin
            || viewerPrimaryRole == .superadmin
        let hasHrOps = viewerCapabilities.contains(.hr_ops)
        if !isSelf && !hasEvalAccess && !hasHrOps {
            accessDenied = true
            return
        }

        do {
            let rows: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            if let first = rows.first {
                self.profile = first
            } else {
                self.accessDenied = true
            }
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
