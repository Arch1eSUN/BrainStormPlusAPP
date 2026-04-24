import SwiftUI

struct AdminAttendanceExemptionEditSheet: View {
    enum Mode {
        case newDepartment(options: [String])
        case newEmployee(options: [AdminAttendanceExemptionViewModel.TeamMember])
        case editDepartment(rule: AttendanceExemptionDepartmentRule)
        case editEmployee(rule: AttendanceExemptionEmployeeRule)
    }

    enum Result {
        case department(rule: AttendanceExemptionDepartmentRule, isNew: Bool)
        case employee(rule: AttendanceExemptionEmployeeRule, isNew: Bool)
    }

    let mode: Mode
    let onSave: (Result) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDepartment: String = ""
    @State private var selectedEmployeeId: String = ""
    @State private var selectedEmployeeName: String = ""
    @State private var skipGeofence: Bool = false
    @State private var flexibleHours: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .newDepartment(let options):
                    Section("选择部门") {
                        if options.isEmpty {
                            Text("无可选部门").foregroundStyle(BsColor.inkMuted)
                        } else {
                            Picker("部门", selection: $selectedDepartment) {
                                Text("请选择").tag("")
                                ForEach(options, id: \.self) { dept in
                                    Text(dept).tag(dept)
                                }
                            }
                        }
                    }
                    toggleSection
                case .newEmployee(let options):
                    Section("选择员工") {
                        if options.isEmpty {
                            Text("无可选员工").foregroundStyle(BsColor.inkMuted)
                        } else {
                            Picker("员工", selection: $selectedEmployeeId) {
                                Text("请选择").tag("")
                                ForEach(options) { member in
                                    Text(member.department.map { "\(member.fullName) (\($0))" } ?? member.fullName)
                                        .tag(member.id)
                                }
                            }
                            .onChange(of: selectedEmployeeId) { _, newId in
                                selectedEmployeeName = options.first(where: { $0.id == newId })?.fullName ?? ""
                            }
                        }
                    }
                    toggleSection
                case .editDepartment(let rule):
                    Section("部门") {
                        HStack {
                            Text(rule.department).font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    toggleSection
                case .editEmployee(let rule):
                    Section("员工") {
                        HStack {
                            Text(rule.name).font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    toggleSection
                }

                Section {
                    Text("豁免规则说明：开启「免围栏」后员工可在任意位置打卡；开启「弹性工时」后不限制打卡时间段。")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Haptic.medium()
                        commit()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var toggleSection: some View {
        Section("豁免项") {
            Toggle(isOn: $skipGeofence) {
                Label("免地理围栏", systemImage: "mappin.slash")
            }
            Toggle(isOn: $flexibleHours) {
                Label("弹性工时", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var title: String {
        switch mode {
        case .newDepartment: return "添加部门豁免"
        case .newEmployee: return "添加员工豁免"
        case .editDepartment: return "编辑部门豁免"
        case .editEmployee: return "编辑员工豁免"
        }
    }

    private var canSave: Bool {
        switch mode {
        case .newDepartment: return !selectedDepartment.isEmpty
        case .newEmployee: return !selectedEmployeeId.isEmpty
        case .editDepartment, .editEmployee: return true
        }
    }

    private func prefill() {
        switch mode {
        case .newDepartment, .newEmployee:
            break
        case .editDepartment(let rule):
            skipGeofence = rule.skip_geofence
            flexibleHours = rule.flexible_hours
        case .editEmployee(let rule):
            skipGeofence = rule.skip_geofence
            flexibleHours = rule.flexible_hours
        }
    }

    private func commit() {
        switch mode {
        case .newDepartment:
            let rule = AttendanceExemptionDepartmentRule(
                department: selectedDepartment,
                skip_geofence: skipGeofence,
                flexible_hours: flexibleHours
            )
            onSave(.department(rule: rule, isNew: true))
        case .newEmployee:
            let rule = AttendanceExemptionEmployeeRule(
                user_id: selectedEmployeeId,
                name: selectedEmployeeName,
                skip_geofence: skipGeofence,
                flexible_hours: flexibleHours
            )
            onSave(.employee(rule: rule, isNew: true))
        case .editDepartment(let existing):
            let rule = AttendanceExemptionDepartmentRule(
                department: existing.department,
                skip_geofence: skipGeofence,
                flexible_hours: flexibleHours
            )
            onSave(.department(rule: rule, isNew: false))
        case .editEmployee(let existing):
            let rule = AttendanceExemptionEmployeeRule(
                user_id: existing.user_id,
                name: existing.name,
                skip_geofence: skipGeofence,
                flexible_hours: flexibleHours
            )
            onSave(.employee(rule: rule, isNew: false))
        }
        dismiss()
    }
}
