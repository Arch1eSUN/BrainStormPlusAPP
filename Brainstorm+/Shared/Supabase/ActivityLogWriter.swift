import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// ActivityLogWriter —— iOS 对齐 Web `writeActivityLog`
//
// Web 来源：BrainStorm+-Web/src/lib/actions/activity-writer.ts
//   └ 写入 `public.activity_log`
//   └ 字段：user_id / type / action / description / entity_type /
//            entity_id / target_id / created_at (默认 now)
//
// 设计原则：
//   • 永不阻塞主流程 —— 失败静默打日志，业务逻辑照常返回
//   • 任何业务 mutation（Tasks/Announcements/Reporting/OKR/Deliverables
//     /Approvals/Payroll/Broadcast）都可 call-in
//   • iOS 通过用户 JWT 写入；Web 通过 server action 写入。schema 相同。
// ══════════════════════════════════════════════════════════════════

public enum ActivityLogWriter {

    /// 供外部 VM 调用的统一入口。不抛异常，失败仅 console 警告。
    ///
    /// - Parameters:
    ///   - client: 当前会话 `SupabaseClient`
    ///   - type: Web `activity-writer.ts` 的 `ActivityType`
    ///   - action: 简短动作标识（如 `create` / `update` / `delete` / `submit`）
    ///   - description: 人类可读描述（≤ 200 字，会显示在 Activity Feed）
    ///   - entityType: 实体类型。默认同 `type`，少数场景（如 `okr` 下 `key_result`）可覆盖
    ///   - entityId: 实体 UUID（如 taskId / objectiveId）
    ///   - targetId: 目标用户 UUID（如 assignee / approver），可选
    public static func write(
        client: SupabaseClient,
        type: ActivityItem.ActivityType,
        action: String,
        description: String,
        entityType: String? = nil,
        entityId: UUID? = nil,
        targetId: UUID? = nil
    ) async {
        do {
            let userId = try await client.auth.session.user.id
            let payload = Payload(
                userId: userId,
                type: type.rawValue,
                action: action,
                description: description,
                entityType: entityType ?? type.rawValue,
                entityId: entityId,
                targetId: targetId
            )

            try await client
                .from("activity_log")
                .insert(payload)
                .execute()
        } catch {
            // 1:1 对齐 Web：活动日志失败绝不破坏主流程
            print("[ActivityLog] 写入失败（非阻塞）：\(error.localizedDescription)")
        }
    }

    /// fire-and-forget 包装 —— 允许在非 async 场景（rare）直接启动任务。
    /// 推荐仍在 VM 中 `await write(...)`；此方法仅为边缘兜底。
    public static func writeDetached(
        client: SupabaseClient,
        type: ActivityItem.ActivityType,
        action: String,
        description: String,
        entityType: String? = nil,
        entityId: UUID? = nil,
        targetId: UUID? = nil
    ) {
        Task.detached(priority: .utility) {
            await write(
                client: client,
                type: type,
                action: action,
                description: description,
                entityType: entityType,
                entityId: entityId,
                targetId: targetId
            )
        }
    }

    // MARK: - Payload

    private struct Payload: Encodable {
        let userId: UUID
        let type: String
        let action: String
        let description: String
        let entityType: String
        let entityId: UUID?
        let targetId: UUID?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case type
            case action
            case description
            case entityType = "entity_type"
            case entityId = "entity_id"
            case targetId = "target_id"
        }
    }
}
