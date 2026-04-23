import Foundation
import Combine
import Supabase

@MainActor
final class AdminAttendanceExemptionViewModel: ObservableObject {
    struct TeamMember: Identifiable, Hashable {
        let id: String
        let fullName: String
        let department: String?
    }

    @Published var config: AttendanceExemptionConfig = .init()
    @Published var departments: [String] = []
    @Published var teamMembers: [TeamMember] = []
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    struct ConfigRow: Decodable {
        let value: AttendanceExemptionConfig?
    }

    struct DeptListRow: Decodable {
        let value: ListWrap?
        struct ListWrap: Decodable { let list: [String]? }
    }

    struct ProfileRow: Decodable {
        let id: UUID
        let full_name: String?
        let department: String?
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let cfgTask: [ConfigRow] = client
                .from("system_configs")
                .select("value")
                .eq("key", value: "attendance_exemptions")
                .limit(1)
                .execute()
                .value

            async let deptTask: [DeptListRow] = client
                .from("system_configs")
                .select("value")
                .eq("key", value: "departments")
                .limit(1)
                .execute()
                .value

            async let profilesTask: [ProfileRow] = client
                .from("profiles")
                .select("id, full_name, department")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value

            let (cfgRows, deptRows, profiles) = try await (cfgTask, deptTask, profilesTask)

            config = cfgRows.first?.value ?? AttendanceExemptionConfig()
            departments = deptRows.first?.value?.list ?? []
            teamMembers = profiles.map {
                TeamMember(id: $0.id.uuidString, fullName: $0.full_name ?? "未命名", department: $0.department)
            }
        } catch {
            errorMessage = "加载豁免配置失败：\(ErrorLocalizer.localize(error))"
        }
    }

    struct UpsertPayload: Encodable {
        let key: String
        let value: AttendanceExemptionConfig
        let updated_at: String
    }

    func save() async -> Bool {
        isSaving = true
        errorMessage = nil
        infoMessage = nil
        defer { isSaving = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let payload = UpsertPayload(
                key: "attendance_exemptions",
                value: config,
                updated_at: iso.string(from: Date())
            )
            _ = try await client
                .from("system_configs")
                .upsert(payload, onConflict: "key")
                .execute()
            infoMessage = "弹性考勤豁免规则已保存"
            return true
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    // MARK: - Department rules
    var availableDepartments: [String] {
        let used = Set(config.department_rules.map { $0.department })
        return departments.filter { !used.contains($0) }
    }

    func addDepartmentRule(_ department: String) {
        let d = department.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty,
              !config.department_rules.contains(where: { $0.department == d }) else { return }
        config.department_rules.append(.init(department: d))
    }

    func removeDepartmentRule(_ department: String) {
        config.department_rules.removeAll { $0.department == department }
    }

    func updateDepartmentRule(_ rule: AttendanceExemptionDepartmentRule) {
        if let idx = config.department_rules.firstIndex(where: { $0.department == rule.department }) {
            config.department_rules[idx] = rule
        }
    }

    // MARK: - Employee rules
    var availableEmployees: [TeamMember] {
        let used = Set(config.employee_rules.map { $0.user_id })
        return teamMembers.filter { !used.contains($0.id) }
    }

    func addEmployeeRule(userId: String) {
        guard let member = teamMembers.first(where: { $0.id == userId }) else { return }
        guard !config.employee_rules.contains(where: { $0.user_id == userId }) else { return }
        config.employee_rules.append(.init(user_id: member.id, name: member.fullName))
    }

    func removeEmployeeRule(userId: String) {
        config.employee_rules.removeAll { $0.user_id == userId }
    }

    func updateEmployeeRule(_ rule: AttendanceExemptionEmployeeRule) {
        if let idx = config.employee_rules.firstIndex(where: { $0.user_id == rule.user_id }) {
            config.employee_rules[idx] = rule
        }
    }
}
