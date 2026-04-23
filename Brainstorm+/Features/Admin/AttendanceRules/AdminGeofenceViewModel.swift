import Foundation
import Combine
import Supabase

@MainActor
final class AdminGeofenceViewModel: ObservableObject {
    @Published var fences: [Geofence] = []
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let client: SupabaseClient
    init(client: SupabaseClient = supabase) { self.client = client }

    struct SettingsRow: Decodable {
        let value: GeofenceValue?
    }

    enum GeofenceValue: Decodable {
        case array([Geofence])
        case object(LegacyObject)
        case null

        struct LegacyObject: Decodable {
            let lat: Double?
            let lng: Double?
            let radius: Int?
            let address: String?
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let arr = try? c.decode([Geofence].self) { self = .array(arr); return }
            if let obj = try? c.decode(LegacyObject.self) { self = .object(obj); return }
            self = .null
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [SettingsRow] = try await client
                .from("system_settings")
                .select("value")
                .eq("key", value: "geo_fence")
                .limit(1)
                .execute()
                .value

            guard let raw = rows.first?.value else {
                fences = []
                return
            }
            switch raw {
            case .array(let arr):
                fences = arr
            case .object(let obj):
                if let addr = obj.address, !addr.isEmpty {
                    fences = [Geofence(
                        id: "legacy-1",
                        name: "主办公区",
                        lat: obj.lat,
                        lng: obj.lng,
                        radius: obj.radius ?? 300,
                        address: addr
                    )]
                } else {
                    fences = []
                }
            case .null:
                fences = []
            }
        } catch {
            errorMessage = "加载地理围栏失败：\(ErrorLocalizer.localize(error))"
        }
    }

    struct UpsertPayload: Encodable {
        let key: String
        let value: [Geofence]
        let description: String
        let updated_at: String
    }

    func save() async -> Bool {
        let valid = fences.filter { $0.isValid }
        if !fences.isEmpty && valid.isEmpty {
            errorMessage = "请至少保留一个已设置坐标的打卡点，或删除空配置"
            return false
        }
        isSaving = true
        errorMessage = nil
        infoMessage = nil
        defer { isSaving = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let payload = UpsertPayload(
                key: "geo_fence",
                value: valid,
                description: "Company global geofence settings",
                updated_at: iso.string(from: Date())
            )
            _ = try await client
                .from("system_settings")
                .upsert(payload, onConflict: "key")
                .execute()
            infoMessage = "多点地理围栏配置已保存"
            fences = valid
            return true
        } catch {
            errorMessage = "保存失败：\(ErrorLocalizer.localize(error))"
            return false
        }
    }

    func addNew() {
        fences.append(Geofence())
    }

    func remove(id: String) {
        fences.removeAll { $0.id == id }
    }

    func update(_ fence: Geofence) {
        if let idx = fences.firstIndex(where: { $0.id == fence.id }) {
            fences[idx] = fence
        } else {
            fences.append(fence)
        }
    }
}
