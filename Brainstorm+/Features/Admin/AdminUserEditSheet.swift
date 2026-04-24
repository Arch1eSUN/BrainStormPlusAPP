import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 编辑用户配置 Sheet
// Parity target: Web admin/page.tsx EditUserModal (L526+).
// Writes go directly to profiles (iOS has no service role). 普通字段（姓名/部门/职位）
// 依赖 RLS policy；角色/能力包由 superadmin 才能提交。
// ══════════════════════════════════════════════════════════════════

public struct AdminUserEditSheet: View {
    let userId: UUID
    let canAssignPrivileges: Bool
    let departments: [String]
    let positions: [String]
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AdminUsersViewModel()

    @State private var loading = true
    @State private var saving = false
    @State private var errorText: String?
    @State private var detail: AdminUserDetail?

    @State private var fullName: String = ""
    @State private var appRole: String = "employee"
    @State private var selectedPackages: Set<AdminCapabilityPackageId> = []
    @State private var excludedCaps: Set<Capability> = []
    @State private var department: String = ""
    @State private var position: String = ""

    public init(
        userId: UUID,
        canAssignPrivileges: Bool,
        departments: [String],
        positions: [String],
        onSuccess: @escaping () -> Void
    ) {
        self.userId = userId
        self.canAssignPrivileges = canAssignPrivileges
        self.departments = departments
        self.positions = positions
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail = detail {
                    form(detail: detail)
                } else {
                    BsEmptyState(
                        title: "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: errorText ?? "无法获取用户信息"
                    )
                }
            }
            .navigationTitle("编辑用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "保存中…" : "保存") {
                        Haptic.medium()
                        Task { await submit() }
                    }
                    .disabled(saving || loading || detail == nil)
                }
            }
            .task {
                await loadDetail()
            }
        }
    }

    @ViewBuilder
    private func form(detail: AdminUserDetail) -> some View {
        Form {
            Section("基本资料") {
                TextField("姓名", text: $fullName)
                    .textInputAutocapitalization(.never)
                LabeledContent("登录用户名", value: detail.displayName ?? "—")
                LabeledContent("邮箱", value: detail.email ?? "—")
            }

            if canAssignPrivileges {
                Section("角色") {
                    Picker("主角色", selection: $appRole) {
                        Text("员工").tag("employee")
                        Text("管理员").tag("admin")
                        Text("超级管理员").tag("superadmin")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appRole) { _, _ in Haptic.selection() }
                }
            } else {
                Section("角色") {
                    LabeledContent("主角色", value: adminAppRoleLabel(appRole))
                }
            }

            if canAssignPrivileges {
                Section {
                    ForEach(AdminCapabilityPackage.all) { pkg in
                        Toggle(isOn: Binding(
                            get: { selectedPackages.contains(pkg.id) },
                            set: { on in
                                if on { selectedPackages.insert(pkg.id) }
                                else { selectedPackages.remove(pkg.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.label).font(.subheadline.weight(.semibold))
                                Text(pkg.description)
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                    }
                } header: {
                    Text("能力包")
                } footer: {
                    Text("按需分配功能权限。已选 \(selectedPackages.count) 个。")
                }

                if let roleEnum = PrimaryRole(rawValue: appRole),
                   let defaults = RBACManager.shared.defaultCapabilities[roleEnum],
                   !defaults.isEmpty {
                    Section {
                        ForEach(defaults, id: \.self) { cap in
                            Toggle(isOn: Binding(
                                get: { !excludedCaps.contains(cap) },
                                set: { on in
                                    if on { excludedCaps.remove(cap) }
                                    else { excludedCaps.insert(cap) }
                                }
                            )) {
                                Text(AdminCapabilityLabels.label(cap))
                                    .font(.subheadline)
                                    .strikethrough(excludedCaps.contains(cap))
                                    .foregroundStyle(excludedCaps.contains(cap) ? BsColor.inkMuted : BsColor.ink)
                            }
                        }
                    } header: {
                        Text("角色默认能力 · 取消勾选 = 对该用户排除")
                    } footer: {
                        Text(excludedCaps.isEmpty ? " " : "已排除 \(excludedCaps.count) 项默认能力")
                    }
                }
            }

            Section("部门与职位") {
                Picker("部门", selection: $department) {
                    Text("未指定").tag("")
                    ForEach(departments, id: \.self) { d in
                        Text(d).tag(d)
                    }
                    if !department.isEmpty, !departments.contains(department) {
                        Text("\(department) (归档)").tag(department)
                    }
                }
                Picker("职位", selection: $position) {
                    Text("未指定").tag("")
                    ForEach(positions, id: \.self) { p in
                        Text(p).tag(p)
                    }
                    if !position.isEmpty, !positions.contains(position) {
                        Text("\(position) (归档)").tag(position)
                    }
                }
            }

            if let err = errorText {
                Section {
                    Text(err).font(.footnote).foregroundStyle(BsColor.danger)
                }
            }
        }
    }

    private func loadDetail() async {
        loading = true
        errorText = nil
        defer { loading = false }

        await vm.loadDepartmentsAndPositions()
        guard let d = await vm.fetchDetail(id: userId) else {
            errorText = vm.errorMessage ?? "未找到用户"
            return
        }
        detail = d
        fullName = d.fullName ?? ""
        appRole = adminDbRoleToAppRole(d.role)
        department = d.department ?? ""
        position = d.position ?? ""

        let caps = (d.capabilities ?? []).compactMap { Capability(rawValue: $0) }
        selectedPackages = Set(AdminCapabilityPackage.matchingPackages(from: caps))
        excludedCaps = Set((d.excludedCapabilities ?? []).compactMap { Capability(rawValue: $0) })
    }

    private func submit() async {
        saving = true
        errorText = nil
        defer { saving = false }

        var updates = AdminUsersViewModel.UpdateConfig()
        updates.fullName = fullName
        updates.department = department
        updates.position = position
        if canAssignPrivileges {
            updates.appRole = appRole
            updates.capabilityPackages = Array(selectedPackages)
            updates.excludedCapabilities = Array(excludedCaps)
        }

        let ok = await vm.updateConfig(userId: userId, updates: updates)
        if ok {
            onSuccess()
            dismiss()
        } else {
            errorText = vm.errorMessage ?? "保存失败"
        }
    }
}
