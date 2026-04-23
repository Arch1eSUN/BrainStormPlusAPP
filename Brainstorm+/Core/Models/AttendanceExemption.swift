import Foundation

public struct AttendanceExemptionDepartmentRule: Identifiable, Hashable, Codable {
    public var department: String
    public var skip_geofence: Bool
    public var flexible_hours: Bool

    public var id: String { department }

    public init(department: String, skip_geofence: Bool = false, flexible_hours: Bool = false) {
        self.department = department
        self.skip_geofence = skip_geofence
        self.flexible_hours = flexible_hours
    }
}

public struct AttendanceExemptionEmployeeRule: Identifiable, Hashable, Codable {
    public var user_id: String
    public var name: String
    public var skip_geofence: Bool
    public var flexible_hours: Bool

    public var id: String { user_id }

    public init(user_id: String, name: String, skip_geofence: Bool = false, flexible_hours: Bool = false) {
        self.user_id = user_id
        self.name = name
        self.skip_geofence = skip_geofence
        self.flexible_hours = flexible_hours
    }
}

public struct AttendanceExemptionConfig: Codable, Hashable {
    public var department_rules: [AttendanceExemptionDepartmentRule]
    public var employee_rules: [AttendanceExemptionEmployeeRule]

    public init(
        department_rules: [AttendanceExemptionDepartmentRule] = [],
        employee_rules: [AttendanceExemptionEmployeeRule] = []
    ) {
        self.department_rules = department_rules
        self.employee_rules = employee_rules
    }
}
