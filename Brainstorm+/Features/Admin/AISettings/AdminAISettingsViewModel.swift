import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.6d — AI 设置 ViewModel
// Parity target: Web `src/components/settings/ai-settings-section.tsx`
//   + `src/lib/actions/ai-actions.ts`
//   + `src/lib/actions/evaluation-config.ts`
//
// RLS reality (027_permission_alignment.sql + 007_ai_provider_system.sql):
//   · api_keys FOR ALL → role = 'superadmin' only (WITH CHECK 同)
//   · 非 superadmin SELECT → is_active = true，且 api_key 字段始终是
//     AES-256-GCM 密文（服务端密钥，iOS 无法解密）
//   · 因此 iOS 策略：
//       - 展示 provider 列表（列出 masked key = 永远打码）
//       - 可切 is_active / default_model / fallback_models（不动 api_key）
//       - 新建 / 改 API key → 引导用户到 Web 端，iOS 不写 api_key
//   · system_configs 写权限 = sensitive_settings_write capability（superadmin 自带）
//     → 月度评分 limits 可在 iOS 直接改
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AdminAISettingsViewModel: ObservableObject {
    // ── Provider row model ──
    public struct ProviderRow: Identifiable, Hashable {
        public let id: UUID
        public var providerName: String
        public var baseUrl: String
        public var maskedApiKey: String   // 永远打码
        public var availableModels: [String]
        public var defaultModel: String?
        public var fallbackModels: [String]
        public var isActive: Bool
        public var createdAt: String?
    }

    public struct EvaluationConfig: Equatable {
        public var enabled: Bool = false
        public var day: Int = 1
        public var hour: Int = 3
    }

    @Published public private(set) var providers: [ProviderRow] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    @Published public var infoMessage: String?
    @Published public var evalConfig: EvaluationConfig = EvaluationConfig()

    public var activeProvider: ProviderRow? {
        providers.first(where: { $0.isActive && $0.defaultModel?.isEmpty == false })
            ?? providers.first(where: { $0.isActive })
    }

    private let client: SupabaseClient
    public init(client: SupabaseClient = supabase) {
        self.client = client
    }

    // ── DTOs ──
    private struct ApiKeyRow: Decodable {
        let id: UUID
        let provider_name: String
        let base_url: String
        let api_key: String?
        let available_models: [String]?
        let default_model: String?
        let fallback_models: [String]?
        let is_active: Bool?
        let created_at: String?
    }

    private struct SystemConfigRow: Decodable {
        let key: String
        let value: AnyJSON?
    }

    // ── Load ──
    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let providersTask: [ApiKeyRow] = client
                .from("api_keys")
                .select("id, provider_name, base_url, api_key, available_models, default_model, fallback_models, is_active, created_at")
                .order("created_at", ascending: false)
                .execute()
                .value

            async let configsTask: [SystemConfigRow] = client
                .from("system_configs")
                .select("key, value")
                .in("key", values: [
                    "evaluations.monthly_enabled",
                    "evaluations.monthly_day",
                    "evaluations.monthly_hour",
                ])
                .execute()
                .value

            let (rows, cfgRows) = try await (providersTask, configsTask)
            providers = rows.map { Self.shape($0) }
            evalConfig = Self.decodeEvaluationConfig(cfgRows)
        } catch {
            errorMessage = "加载 AI 设置失败：\(ErrorLocalizer.localize(error))"
        }
    }

    // ── Mutations (non-key fields only) ──
    private struct TogglePayload: Encodable { let is_active: Bool }
    private struct DefaultModelPayload: Encodable { let default_model: String }
    private struct FallbackPayload: Encodable { let fallback_models: [String] }

    public func toggleActive(providerId: UUID, to newValue: Bool) async {
        await patchProvider(id: providerId, payload: TogglePayload(is_active: newValue))
    }

    public func setDefaultModel(providerId: UUID, model: String) async {
        await patchProvider(id: providerId, payload: DefaultModelPayload(default_model: model))
    }

    public func saveFallbackModels(providerId: UUID, models: [String]) async {
        await patchProvider(id: providerId, payload: FallbackPayload(fallback_models: models))
    }

    public func deleteProvider(providerId: UUID) async {
        isSaving = true
        errorMessage = nil
        infoMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client
                .from("api_keys")
                .delete()
                .eq("id", value: providerId.uuidString)
                .execute()
            infoMessage = "已删除"
            await load()
        } catch {
            errorMessage = "删除失败：\(ErrorLocalizer.localize(error))"
        }
    }

    private func patchProvider<T: Encodable>(id: UUID, payload: T) async {
        isSaving = true
        errorMessage = nil
        infoMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client
                .from("api_keys")
                .update(payload)
                .eq("id", value: id.uuidString)
                .execute()
            infoMessage = "已保存"
            await load()
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
        }
    }

    // ── Evaluation config (system_configs) ──
    private struct EvalConfigUpsert: Encodable {
        let key: String
        let value: AnyJSON
        let updated_at: String
    }

    public func saveEvaluationEnabled(_ enabled: Bool) async {
        await upsertSystemConfig(key: "evaluations.monthly_enabled", value: .bool(enabled))
    }

    public func saveEvaluationDay(_ day: Int) async {
        let clamped = max(1, min(28, day))
        await upsertSystemConfig(key: "evaluations.monthly_day", value: .integer(clamped))
    }

    public func saveEvaluationHour(_ hour: Int) async {
        let clamped = max(0, min(23, hour))
        await upsertSystemConfig(key: "evaluations.monthly_hour", value: .integer(clamped))
    }

    private func upsertSystemConfig(key: String, value: AnyJSON) async {
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
                    EvalConfigUpsert(key: key, value: value, updated_at: now),
                    onConflict: "key"
                )
                .execute()
            infoMessage = "已保存"
            await reloadEvaluationConfig()
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
        }
    }

    private func reloadEvaluationConfig() async {
        do {
            let rows: [SystemConfigRow] = try await client
                .from("system_configs")
                .select("key, value")
                .in("key", values: [
                    "evaluations.monthly_enabled",
                    "evaluations.monthly_day",
                    "evaluations.monthly_hour",
                ])
                .execute()
                .value
            evalConfig = Self.decodeEvaluationConfig(rows)
        } catch {
            // Keep stale config; error shown from primary upsert path already
        }
    }

    // ── Helpers ──
    private static func shape(_ row: ApiKeyRow) -> ProviderRow {
        let raw = row.api_key ?? ""
        let masked: String
        if raw.isEmpty {
            masked = "—"
        } else if raw.count <= 8 {
            masked = String(repeating: "•", count: 8)
        } else {
            let suffix = raw.suffix(4)
            masked = "••••••••\(suffix)"
        }
        return ProviderRow(
            id: row.id,
            providerName: row.provider_name,
            baseUrl: row.base_url,
            maskedApiKey: masked,
            availableModels: row.available_models ?? [],
            defaultModel: row.default_model,
            fallbackModels: row.fallback_models ?? [],
            isActive: row.is_active ?? true,
            createdAt: row.created_at
        )
    }

    private static func decodeEvaluationConfig(_ rows: [SystemConfigRow]) -> EvaluationConfig {
        var cfg = EvaluationConfig()
        for r in rows {
            switch r.key {
            case "evaluations.monthly_enabled":
                if case .bool(let b) = r.value { cfg.enabled = b }
                else if case .string(let s) = r.value { cfg.enabled = (s == "true") }
            case "evaluations.monthly_day":
                if case .integer(let n) = r.value { cfg.day = n }
                else if case .double(let d) = r.value { cfg.day = Int(d) }
            case "evaluations.monthly_hour":
                if case .integer(let n) = r.value { cfg.hour = n }
                else if case .double(let d) = r.value { cfg.hour = Int(d) }
            default: break
            }
        }
        return cfg
    }
}
