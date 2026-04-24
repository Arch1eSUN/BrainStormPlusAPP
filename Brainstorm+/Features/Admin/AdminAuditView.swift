import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 操作审计
// Parity target: Web admin/page.tsx AuditPanel (L1144+) +
// `src/lib/actions/admin-audit.ts fetchAdminAuditLogs`.
// 读取 activity_log type='system'；RLS 兜底（需要 admin+）。
// ══════════════════════════════════════════════════════════════════

public struct AuditLogRow: Decodable, Identifiable, Hashable {
    public let id: UUID
    public let type: String
    public let action: String
    public let description: String
    public let userId: UUID?
    public let targetId: UUID?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case action
        case description
        case userId = "user_id"
        case targetId = "target_id"
        case createdAt = "created_at"
    }
}

@MainActor
final class AdminAuditViewModel: ObservableObject {
    @Published var rows: [AuditLogRow] = []
    @Published var actorNames: [UUID: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    struct ProfileName: Decodable, Identifiable {
        let id: UUID
        let fullName: String?
        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
        }
    }

    func load(limit: Int = 100) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let res: [AuditLogRow] = try await client
                .from("activity_log")
                .select("id, type, action, description, user_id, target_id, created_at")
                .eq("type", value: "system")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            rows = res
            let actorIds = Array(Set(res.compactMap { $0.userId }))
            if !actorIds.isEmpty {
                let profiles: [ProfileName] = try await client
                    .from("profiles")
                    .select("id, full_name")
                    .in("id", values: actorIds.map { $0.uuidString })
                    .execute()
                    .value
                actorNames = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.fullName ?? "") })
            } else {
                actorNames = [:]
            }
        } catch {
            errorMessage = "加载审计日志失败：\(ErrorLocalizer.localize(error))"
        }
    }
}

public struct AdminAuditView: View {
    @StateObject private var vm = AdminAuditViewModel()

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
        Group {
            if vm.isLoading && vm.rows.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.rows.isEmpty {
                ContentUnavailableView(
                    "暂无审计记录",
                    systemImage: "list.bullet.clipboard",
                    description: Text("管理操作（角色变更、用户创建、配置修改等）将自动记录在此")
                )
            } else {
                List {
                    Section {
                        ForEach(vm.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    actionTag(row.action)
                                    Text(row.description)
                                        .font(.subheadline)
                                        .lineLimit(3)
                                }
                                HStack(spacing: 10) {
                                    let actor = row.userId.flatMap { vm.actorNames[$0] } ?? "系统"
                                    Label(actor.isEmpty ? "系统" : actor, systemImage: "person.crop.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let ts = row.createdAt {
                                        Label(dateLabel(ts), systemImage: "clock")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("共 \(vm.rows.count) 条记录")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("操作审计")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    @ViewBuilder
    private func actionTag(_ action: String) -> some View {
        let (label, color): (String, Color) = {
            switch action {
            case "role_change": return ("角色变更", .purple)
            case "user_create": return ("创建用户", .green)
            case "user_deactivate": return ("禁用账号", .red)
            case "config_update": return ("配置变更", .orange)
            case "broadcast": return ("广播通知", .blue)
            default: return (action, .gray)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM月dd日 HH:mm"
        return f.string(from: date)
    }
}
