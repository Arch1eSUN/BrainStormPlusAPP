import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 用户管理 VM.
// Parity target: Web `src/lib/actions/admin.ts` fetchAdminUsers /
// adminUpdateRole / adminCreateUser / adminDeleteUser /
// adminPermanentDeleteUser / fetchUserProfile / adminUpdateUserConfig.
//
// 数据库约束笔记（非显然）：
//   - email 字段存在 auth.users；iOS 客户端无 admin key，不能 listUsers。
//     这里只从 profiles 拉 display_name/full_name 等字段；列表不再尝试
//     去 auth.users 拼 email（Web 用 service role 做了这件事）。
//   - adminPermanentDeleteUser 在 Web 端要求 super admin + 清理 20+ 张关联表。
//     iOS 客户端无 service role，无法真正删除 auth user；所以"删除账号"
//     在 iOS 上降级为 status='deleted' 软删，并在 UI 文案上明示。真正的
//     物理删除仍需在 Web 侧操作。
// ══════════════════════════════════════════════════════════════════

public struct AdminUserRow: Decodable, Identifiable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let displayName: String?
    public let email: String?
    public let role: String?
    public let department: String?
    public let position: String?
    public let status: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case displayName = "display_name"
        case email
        case role
        case department
        case position
        case status
        case createdAt = "created_at"
    }
}

public struct AdminUserDetail: Decodable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let displayName: String?
    public let email: String?
    public let role: String?
    public let department: String?
    public let position: String?
    public let status: String?
    public let capabilities: [String]?
    public let excludedCapabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case displayName = "display_name"
        case email
        case role
        case department
        case position
        case status
        case capabilities
        case excludedCapabilities = "excluded_capabilities"
    }
}

@MainActor
public final class AdminUsersViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var roleFilter: String = "" // "", employee, admin, superadmin
    @Published public private(set) var users: [AdminUserRow] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    @Published public var departmentsList: [String] = []
    @Published public var positionsList: [String] = []

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    public var filteredUsers: [AdminUserRow] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { u in
            let haystack = [u.fullName, u.displayName, u.department, u.position, u.email]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(q)
        }
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let base = client
                .from("profiles")
                .select("id, full_name, display_name, email, role, department, position, status, created_at")

            let rows: [AdminUserRow]
            if roleFilter.isEmpty {
                rows = try await base
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } else {
                let variants = dbRoleVariants(forAppRole: roleFilter)
                if variants.count == 1 {
                    rows = try await base
                        .eq("role", value: variants[0])
                        .order("created_at", ascending: false)
                        .execute()
                        .value
                } else {
                    rows = try await base
                        .in("role", values: variants)
                        .order("created_at", ascending: false)
                        .execute()
                        .value
                }
            }
            users = rows
            await loadDepartmentsAndPositions()
        } catch {
            errorMessage = "加载用户列表失败：\(ErrorLocalizer.localize(error))"
        }
    }

    public func loadDepartmentsAndPositions() async {
        do {
            async let dTask = fetchConfigList(key: "departments")
            async let pTask = fetchConfigList(key: "positions")
            let (d, p) = try await (dTask, pTask)
            departmentsList = d
            positionsList = p
        } catch {
            // non-fatal
        }
    }

    private func fetchConfigList(key: String) async throws -> [String] {
        struct Row: Decodable { let value: ListValue?
            struct ListValue: Decodable { let list: [String]? }
        }
        let rows: [Row] = try await client
            .from("system_configs")
            .select("value")
            .eq("key", value: key)
            .limit(1)
            .execute()
            .value
        return rows.first?.value?.list ?? []
    }

    // ── Fetch one profile for edit sheet (with effective capability set) ──
    public func fetchDetail(id: UUID) async -> AdminUserDetail? {
        do {
            let rows: [AdminUserDetail] = try await client
                .from("profiles")
                .select("id, full_name, display_name, email, role, department, position, status, capabilities, excluded_capabilities")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            errorMessage = "加载用户详情失败：\(ErrorLocalizer.localize(error))"
            return nil
        }
    }

    // ── Role change (superadmin only; server-side RLS enforces) ──
    public func updateRole(userId: UUID, appRole: String) async -> Bool {
        do {
            struct Payload: Encodable { let role: String }
            _ = try await client
                .from("profiles")
                .update(Payload(role: appRole))
                .eq("id", value: userId.uuidString)
                .execute()
            await writeAudit(action: "role_change", description: "将用户角色变更为 \(appRole)", targetId: userId)
            return true
        } catch {
            errorMessage = "更新角色失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    // ── Soft-deactivate: status=inactive ──
    public func deactivate(userId: UUID) async -> Bool {
        do {
            struct Payload: Encodable { let status: String }
            _ = try await client
                .from("profiles")
                .update(Payload(status: "inactive"))
                .eq("id", value: userId.uuidString)
                .execute()
            await writeAudit(action: "user_deactivate", description: "停用用户", targetId: userId)
            return true
        } catch {
            errorMessage = "禁用用户失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    // ── Soft-delete: status=deleted (iOS 客户端无 service role, 不能物理删除) ──
    public func softDelete(userId: UUID, targetName: String) async -> Bool {
        do {
            struct Payload: Encodable { let status: String }
            _ = try await client
                .from("profiles")
                .update(Payload(status: "deleted"))
                .eq("id", value: userId.uuidString)
                .execute()
            await writeAudit(
                action: "user_deactivate",
                description: "标记删除用户 \(targetName)（iOS 软删，物理清理请在 Web 端完成）",
                targetId: userId
            )
            return true
        } catch {
            errorMessage = "删除用户失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    // ── Update user config (role/caps/dept/position/name) ──
    public struct UpdateConfig {
        public var appRole: String?
        public var capabilityPackages: [AdminCapabilityPackageId]?
        public var excludedCapabilities: [Capability]?
        public var department: String?
        public var position: String?
        public var fullName: String?
    }

    public func updateConfig(userId: UUID, updates: UpdateConfig) async -> Bool {
        // Build a dynamic JSON payload (mirroring adminUpdateUserConfig)
        struct Payload: Encodable {
            let role: String?
            let capabilities: [String]?
            let excluded_capabilities: [String]?
            let department: String?
            let position: String?
            let full_name: String?
            let updated_at: String
        }
        var resolvedCaps: [String]? = nil
        if let pkgs = updates.capabilityPackages {
            resolvedCaps = pkgs.isEmpty ? [] : AdminCapabilityPackages_ResolveRaw(pkgs)
        }
        let payload = Payload(
            role: updates.appRole,
            capabilities: resolvedCaps,
            excluded_capabilities: updates.excludedCapabilities?.map(\.rawValue),
            department: updates.department,
            position: updates.position,
            full_name: updates.fullName,
            updated_at: iso8601Now()
        )
        do {
            _ = try await client
                .from("profiles")
                .update(payload)
                .eq("id", value: userId.uuidString)
                .execute()
            var bits: [String] = []
            if let r = updates.appRole { bits.append("角色→\(r)") }
            if updates.capabilityPackages != nil { bits.append("能力包更新") }
            if let ex = updates.excludedCapabilities { bits.append("排除(\(ex.count))") }
            if let d = updates.department { bits.append("部门→\(d.isEmpty ? "无" : d)") }
            if let p = updates.position { bits.append("职位→\(p.isEmpty ? "无" : p)") }
            if let n = updates.fullName { bits.append("姓名→\(n)") }
            await writeAudit(
                action: "config_update",
                description: "更新用户配置: \(bits.joined(separator: ", "))",
                targetId: userId
            )
            return true
        } catch {
            errorMessage = "保存配置失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    // ── Audit helper ──
    private func writeAudit(action: String, description: String, targetId: UUID?) async {
        struct Payload: Encodable {
            let type: String
            let action: String
            let description: String
            let user_id: String
            let target_id: String?
        }
        guard let session = try? await client.auth.session else { return }
        let callerId = session.user.id.uuidString
        let payload = Payload(
            type: "system",
            action: action,
            description: description,
            user_id: callerId,
            target_id: targetId?.uuidString
        )
        _ = try? await client.from("activity_log").insert(payload).execute()
    }

    // ── App role ↔ DB role mapping (mirror admin.ts L183) ──
    private func dbRoleVariants(forAppRole appRole: String) -> [String] {
        switch appRole {
        case "superadmin": return ["superadmin", "super_admin"]
        case "admin": return ["admin", "manager", "team_lead"]
        case "employee": return ["employee", "hr", "finance", "intern", "contractor"]
        default: return [appRole]
        }
    }

    private func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

// Free function to avoid capturing the VM namespace for an encode step
private func AdminCapabilityPackages_ResolveRaw(_ ids: [AdminCapabilityPackageId]) -> [String] {
    AdminCapabilityPackage.resolve(ids).map(\.rawValue)
}

public func adminDbRoleToAppRole(_ dbRole: String?) -> String {
    guard let raw = dbRole?.lowercased() else { return "employee" }
    if ["superadmin", "admin", "employee"].contains(raw) { return raw }
    switch raw {
    case "chairperson", "super_admin": return "superadmin"
    case "manager", "team_lead": return "admin"
    default: return "employee"
    }
}

public func adminAppRoleLabel(_ appRole: String) -> String {
    switch appRole {
    case "superadmin": return "超级管理员"
    case "admin": return "管理员"
    case "employee": return "员工"
    default: return appRole
    }
}
