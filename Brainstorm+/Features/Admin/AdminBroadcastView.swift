import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 广播通知
// Parity target: Web `src/lib/actions/system-config.ts broadcastNotification`。
// 选择类型 → 向所有 status=active 的 profiles.id 批量 insert notifications.
// 需要 admin+ 主角色（server 侧为 safeGuard requiredPrimaryRole: 'admin'）。
// ══════════════════════════════════════════════════════════════════

@MainActor
final class AdminBroadcastViewModel: ObservableObject {
    enum NotifType: String, CaseIterable, Identifiable {
        case info, success, warning, error
        var id: String { rawValue }
        var label: String {
            switch self {
            case .info: return "通知"
            case .success: return "成功"
            case .warning: return "警告"
            case .error: return "错误"
            }
        }
    }

    @Published var title: String = ""
    @Published var body: String = ""
    @Published var type: NotifType = .info
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var info: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    struct ProfileIdRow: Decodable { let id: UUID }
    struct NotificationPayload: Encodable {
        let user_id: String
        let title: String
        let body: String
        let type: String
        let link: String
    }

    func send() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else {
            errorMessage = "标题和内容都不能为空"
            return
        }
        isSending = true
        errorMessage = nil
        info = nil
        defer { isSending = false }

        do {
            let profiles: [ProfileIdRow] = try await client
                .from("profiles")
                .select("id")
                .eq("status", value: "active")
                .execute()
                .value
            if profiles.isEmpty {
                errorMessage = "没有活跃用户"
                return
            }
            let payloads = profiles.map {
                NotificationPayload(
                    user_id: $0.id.uuidString,
                    title: trimmedTitle,
                    body: trimmedBody,
                    type: type.rawValue,
                    link: "/dashboard/notifications"
                )
            }
            _ = try await client.from("notifications").insert(payloads).execute()
            info = "已推送给 \(payloads.count) 位用户"

            // Activity log — record the broadcast before we clear the form,
            // so we still have `trimmedTitle` / count for the description.
            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "broadcast",
                description: "向 \(payloads.count) 人发送了广播：\(trimmedTitle)",
                entityType: "broadcast",
                entityId: nil
            )

            title = ""
            body = ""
        } catch {
            errorMessage = "广播失败：\(ErrorLocalizer.localize(error))"
        }
    }
}

public struct AdminBroadcastView: View {
    @StateObject private var vm = AdminBroadcastViewModel()

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        Form {
            Section("消息") {
                TextField("标题", text: $vm.title)
                ZStack(alignment: .topLeading) {
                    if vm.body.isEmpty {
                        Text("正文内容…")
                            .foregroundStyle(BsColor.inkMuted)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $vm.body)
                        .frame(minHeight: 120)
                }
                Picker("类型", selection: $vm.type) {
                    ForEach(AdminBroadcastViewModel.NotifType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.type) { _, _ in Haptic.selection() }
            }

            if let info = vm.info {
                Section {
                    Label(info, systemImage: "checkmark.circle").foregroundStyle(BsColor.success)
                }
            }

            Section {
                Button {
                    Haptic.medium()
                    Task { await vm.send() }
                } label: {
                    HStack {
                        Spacer()
                        if vm.isSending {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(vm.isSending ? "发送中…" : "推送给全体活跃用户")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
                .disabled(vm.isSending)
            }
        }
        .navigationTitle("广播通知")
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($vm.errorMessage)
    }
}
