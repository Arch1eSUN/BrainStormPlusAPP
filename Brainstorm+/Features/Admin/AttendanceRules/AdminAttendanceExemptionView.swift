import SwiftUI

public struct AdminAttendanceExemptionView: View {
    @StateObject private var vm = AdminAttendanceExemptionViewModel()
    @State private var showEditSheet: Bool = false
    @State private var editingKind: ExemptionEditKind = .newDepartment

    public init() {}

    enum ExemptionEditKind: Equatable {
        case newDepartment
        case newEmployee
        case editDepartment(String)
        case editEmployee(String)
    }

    public var body: some View {
        List {
            Section {
                Text("为特定部门或员工设置考勤豁免。员工级规则优先级高于部门级。未在此列表中的人员将遵守全局考勤规则。")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }

            Section {
                if vm.config.department_rules.isEmpty {
                    Text("暂无部门级豁免规则")
                        .font(.subheadline)
                        .foregroundStyle(BsColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(vm.config.department_rules) { rule in
                        departmentRow(rule)
                    }
                }
                Button {
                    editingKind = .newDepartment
                    showEditSheet = true
                } label: {
                    Label("添加部门", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(vm.availableDepartments.isEmpty)
            } header: {
                Label("部门级豁免", systemImage: "person.3.fill")
            } footer: {
                if vm.availableDepartments.isEmpty && !vm.departments.isEmpty {
                    Text("所有部门已加入豁免列表")
                        .font(.caption2)
                }
            }

            Section {
                if vm.config.employee_rules.isEmpty {
                    Text("暂无员工级豁免规则")
                        .font(.subheadline)
                        .foregroundStyle(BsColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(vm.config.employee_rules) { rule in
                        employeeRow(rule)
                    }
                }
                Button {
                    editingKind = .newEmployee
                    showEditSheet = true
                } label: {
                    Label("添加员工", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(vm.availableEmployees.isEmpty)
            } header: {
                Label("员工级豁免（优先级高于部门）", systemImage: "person.fill")
            }

            if let info = vm.infoMessage {
                Section {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(BsColor.success)
                }
            }
        }
        .navigationTitle("弹性考勤豁免")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { _ = await vm.save() }
                } label: {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(vm.isSaving || vm.isLoading)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            exemptionSheet
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    @ViewBuilder
    private func departmentRow(_ rule: AttendanceExemptionDepartmentRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.department)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    editingKind = .editDepartment(rule.department)
                    showEditSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                toggleChip(label: "免围栏", systemImage: "mappin.slash", isOn: rule.skip_geofence)
                toggleChip(label: "弹性工时", systemImage: "clock.arrow.circlepath", isOn: rule.flexible_hours)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.removeDepartmentRule(rule.department)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func employeeRow(_ rule: AttendanceExemptionEmployeeRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    editingKind = .editEmployee(rule.user_id)
                    showEditSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                toggleChip(label: "免围栏", systemImage: "mappin.slash", isOn: rule.skip_geofence)
                toggleChip(label: "弹性工时", systemImage: "clock.arrow.circlepath", isOn: rule.flexible_hours)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.removeEmployeeRule(userId: rule.user_id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func toggleChip(label: String, systemImage: String, isOn: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(isOn ? BsColor.brandAzure.opacity(0.15) : Color.secondary.opacity(0.1))
        )
        .foregroundStyle(isOn ? BsColor.brandAzure : Color.secondary)
    }

    @ViewBuilder
    private var exemptionSheet: some View {
        switch editingKind {
        case .newDepartment:
            AdminAttendanceExemptionEditSheet(
                mode: .newDepartment(options: vm.availableDepartments)
            ) { result in
                apply(result)
            }
        case .newEmployee:
            AdminAttendanceExemptionEditSheet(
                mode: .newEmployee(options: vm.availableEmployees)
            ) { result in
                apply(result)
            }
        case .editDepartment(let department):
            if let existing = vm.config.department_rules.first(where: { $0.department == department }) {
                AdminAttendanceExemptionEditSheet(
                    mode: .editDepartment(rule: existing)
                ) { result in
                    apply(result)
                }
            }
        case .editEmployee(let userId):
            if let existing = vm.config.employee_rules.first(where: { $0.user_id == userId }) {
                AdminAttendanceExemptionEditSheet(
                    mode: .editEmployee(rule: existing)
                ) { result in
                    apply(result)
                }
            }
        }
    }

    private func apply(_ result: AdminAttendanceExemptionEditSheet.Result) {
        switch result {
        case .department(let rule, let isNew):
            if isNew {
                vm.config.department_rules.append(rule)
            } else {
                vm.updateDepartmentRule(rule)
            }
        case .employee(let rule, let isNew):
            if isNew {
                vm.config.employee_rules.append(rule)
            } else {
                vm.updateEmployeeRule(rule)
            }
        }
    }
}
