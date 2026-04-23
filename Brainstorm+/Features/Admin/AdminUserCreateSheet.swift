import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 创建用户 Sheet
// Parity target: Web admin/page.tsx CreateUserModal (L830+).
//
// ⚠️ 约束说明（非显然的数据库约束）：
//   Web 侧 adminCreateUser 使用 Supabase service_role 调 auth.admin.createUser，
//   iOS 客户端没有也不该持有 service_role key（anon key 仅能做普通 auth.signUp）。
//   所以 iOS 端的"创建用户"走：POST ${webAPIBaseURL}/api/admin/create-user
//   如果该 route 未落地，这里会明确提示并回退到 Web 端创建。
//
// 暂不做 RPC 重构（见任务 Step 6），提供一个占位表单 + 明确提示。
// 如果 Web 端 route 已上线，直接填入 JWT 转发即可打通。
// ══════════════════════════════════════════════════════════════════

public struct AdminUserCreateSheet: View {
    let canAssignPrivileges: Bool
    let departments: [String]
    let positions: [String]
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var fullName: String = ""
    @State private var displayName: String = ""
    @State private var appRole: String = "employee"
    @State private var department: String = ""
    @State private var position: String = ""
    @State private var selectedPackages: Set<AdminCapabilityPackageId> = []
    @State private var showPassword: Bool = false
    @State private var submitting: Bool = false
    @State private var errorText: String?
    @State private var infoText: String?

    public init(
        canAssignPrivileges: Bool,
        departments: [String],
        positions: [String],
        onSuccess: @escaping () -> Void
    ) {
        self.canAssignPrivileges = canAssignPrivileges
        self.departments = departments
        self.positions = positions
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("iOS 端受 Supabase service_role 限制，无法直接在设备上创建 auth 账号。请在 Web 端 /dashboard/admin 完成创建；iOS 端负责后续的角色、能力包、部门、职位配置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("创建流程说明")
                }

                Section("基本资料") {
                    TextField("姓名", text: $fullName)
                    TextField("登录用户名", text: $displayName)
                        .textInputAutocapitalization(.never)
                    TextField("登录邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    HStack {
                        if showPassword {
                            TextField("初始密码 (至少 6 位)", text: $password)
                        } else {
                            SecureField("初始密码 (至少 6 位)", text: $password)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if canAssignPrivileges {
                    Section("角色") {
                        Picker("主角色", selection: $appRole) {
                            Text("员工").tag("employee")
                            Text("管理员").tag("admin")
                            Text("超级管理员").tag("superadmin")
                        }
                        .pickerStyle(.segmented)
                    }

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
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("能力包")
                    }
                }

                Section("部门与职位") {
                    Picker("部门", selection: $department) {
                        Text("未指定").tag("")
                        ForEach(departments, id: \.self) { d in
                            Text(d).tag(d)
                        }
                    }
                    Picker("职位", selection: $position) {
                        Text("未指定").tag("")
                        ForEach(positions, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                }

                if let info = infoText {
                    Section {
                        Text(info).font(.footnote).foregroundStyle(.orange)
                    }
                }
                if let err = errorText {
                    Section {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("创建用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(submitting ? "提交中…" : "创建") {
                        Task { await submit() }
                    }
                    .disabled(submitting || fullName.isEmpty || displayName.isEmpty || email.isEmpty || password.count < 6)
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        errorText = nil
        infoText = nil
        defer { submitting = false }

        // Attempt to proxy through Web API (/api/admin/create-user).
        // If未落地，提示用户改用 Web 端操作。
        do {
            let url = AppEnvironment.webAPIBaseURL.appendingPathComponent("api/admin/create-user")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let session = try? await supabase.auth.session {
                req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "email": email,
                "password": password,
                "full_name": fullName,
                "display_name": displayName,
                "role": canAssignPrivileges ? appRole : "employee",
                "department": department,
                "position": position,
                "capability_packages": Array(selectedPackages).map(\.rawValue)
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http.statusCode == 404 {
                infoText = "Web 端 /api/admin/create-user 尚未上线。请在浏览器 /dashboard/admin 创建用户后，回来编辑配置。"
                return
            }
            if http.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                errorText = "创建失败：\(msg)"
                return
            }
            onSuccess()
            dismiss()
        } catch {
            errorText = "创建失败：\(ErrorLocalizer.localize(error))"
        }
    }
}
