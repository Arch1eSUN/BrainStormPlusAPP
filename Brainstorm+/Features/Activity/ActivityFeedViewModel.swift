import Foundation
import Combine
import Supabase

@MainActor
public final class ActivityFeedViewModel: ObservableObject {
    @Published public var items: [ActivityItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var filter: ActivityItem.ActivityType? = nil

    private let client: SupabaseClient
    private let fetchLimit: Int

    public init(client: SupabaseClient, fetchLimit: Int = 50) {
        self.client = client
        self.fetchLimit = fetchLimit
    }

    public var filteredItems: [ActivityItem] {
        guard let filter else { return items }
        return items.filter { $0.type == filter }
    }

    /// Ordered list of (dateLabel, items) groups — preserves descending
    /// chronological order because we iterate already-sorted `filteredItems`.
    public var grouped: [(label: String, items: [ActivityItem])] {
        var order: [String] = []
        var bucket: [String: [ActivityItem]] = [:]
        for item in filteredItems {
            let label = Self.dateLabelFormatter.string(from: item.createdAt)
            if bucket[label] == nil {
                order.append(label)
                bucket[label] = []
            }
            bucket[label]?.append(item)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let rows: [ActivityItem] = try await client
                .from("activity_log")
                .select("*, profiles:user_id(full_name, avatar_url)")
                .order("created_at", ascending: false)
                .limit(fetchLimit)
                .execute()
                .value
            self.items = rows
        } catch {
            // Iter 7 §C.2 — silent CancellationError tier; banner 不闪屏。
            self.errorMessage = ErrorPresenter.userFacingMessage(error) ?? self.errorMessage
        }
        isLoading = false
    }

    // MARK: - Formatters

    /// zh_CN equivalent of Web `toLocaleDateString('zh-CN', { month: 'long',
    /// day: 'numeric', weekday: 'long' })` — e.g. "4月23日 星期三".
    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}
