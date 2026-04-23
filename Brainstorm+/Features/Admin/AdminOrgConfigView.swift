import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 组织架构（部门 + 职位）
// Parity target: Web `components/settings/org-config-section.tsx`.
// 直接读写 system_configs.value.list（key = departments / positions）。
// 写入需要 sensitive_settings_write capability；RLS 兜底。
// ══════════════════════════════════════════════════════════════════

@MainActor
final class AdminOrgConfigViewModel: ObservableObject {
    @Published var departments: [String] = []
    @Published var positions: [String] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    struct ConfigRow: Decodable {
        let value: ListWrap?
        struct ListWrap: Decodable { let list: [String]? }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let d: [ConfigRow] = client
                .from("system_configs")
                .select("value")
                .eq("key", value: "departments")
                .limit(1)
                .execute()
                .value
            async let p: [ConfigRow] = client
                .from("system_configs")
                .select("value")
                .eq("key", value: "positions")
                .limit(1)
                .execute()
                .value
            let (dRes, pRes) = try await (d, p)
            departments = dRes.first?.value?.list ?? []
            positions = pRes.first?.value?.list ?? []
        } catch {
            errorMessage = "加载组织架构失败：\(ErrorLocalizer.localize(error))"
        }
    }

    struct UpsertPayload: Encodable {
        let key: String
        let value: ValueWrap
        let updated_at: String
        struct ValueWrap: Encodable { let list: [String] }
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        infoMessage = nil
        defer { isSaving = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let now = iso.string(from: Date())
            _ = try await client
                .from("system_configs")
                .upsert(
                    UpsertPayload(key: "departments", value: .init(list: departments), updated_at: now),
                    onConflict: "key"
                )
                .execute()
            _ = try await client
                .from("system_configs")
                .upsert(
                    UpsertPayload(key: "positions", value: .init(list: positions), updated_at: now),
                    onConflict: "key"
                )
                .execute()
            infoMessage = "已保存"
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
        }
    }
}

public struct AdminOrgConfigView: View {
    @StateObject private var vm = AdminOrgConfigViewModel()
    @State private var newDept: String = ""
    @State private var newPosition: String = ""

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(Array(vm.departments.enumerated()), id: \.offset) { idx, dept in
                    HStack {
                        Text(dept)
                        Spacer()
                        Button(role: .destructive) {
                            vm.departments.remove(at: idx)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("新增部门", text: $newDept)
                    Button("添加") {
                        let name = newDept.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty, !vm.departments.contains(name) {
                            vm.departments.append(name)
                            newDept = ""
                        }
                    }
                    .disabled(newDept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("部门 (共 \(vm.departments.count) 个)")
            }

            Section {
                ForEach(Array(vm.positions.enumerated()), id: \.offset) { idx, pos in
                    HStack {
                        Text(pos)
                        Spacer()
                        Button(role: .destructive) {
                            vm.positions.remove(at: idx)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("新增职位", text: $newPosition)
                    Button("添加") {
                        let name = newPosition.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty, !vm.positions.contains(name) {
                            vm.positions.append(name)
                            newPosition = ""
                        }
                    }
                    .disabled(newPosition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("职位 (共 \(vm.positions.count) 个)")
            }

            if let info = vm.infoMessage {
                Section {
                    Label(info, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("组织架构")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.isSaving ? "保存中…" : "保存") {
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving || vm.isLoading)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }
}
