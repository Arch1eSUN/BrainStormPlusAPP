import Foundation
import Supabase

/// Phase 1.2 — central wrapper for new chat RPCs (edit, mute, pin, search).
///
/// Why a separate service vs growing `ChatRoomViewModel`:
///   • mute / pin / search are list-level actions — `ChatListViewModel` calls
///     them too, and we don't want to duplicate the encoder structs.
///   • edit is room-level but the call surface is identical.
/// One thin layer keeps RPC param structs in one place; both VMs depend on it.
public actor MessagesService {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Edit message (5-min window, sender-only)

    public func editMessage(messageId: UUID, newContent: String) async throws {
        struct Params: Encodable {
            let p_message_id: String
            let p_new_content: String
        }
        try await client
            .rpc("chat_edit_message",
                 params: Params(p_message_id: messageId.uuidString,
                                p_new_content: newContent))
            .execute()
    }

    // MARK: - Per-channel mute

    public func setChannelMuted(channelId: UUID, until: Date?) async throws {
        struct Params: Encodable {
            let p_channel_id: String
            let p_muted_until: String?
        }
        let iso: String? = until.map { ISO8601DateFormatter().string(from: $0) }
        try await client
            .rpc("chat_set_channel_muted",
                 params: Params(p_channel_id: channelId.uuidString,
                                p_muted_until: iso))
            .execute()
    }

    // MARK: - Channel pin

    public func setChannelPinned(channelId: UUID, pinned: Bool) async throws {
        struct Params: Encodable {
            let p_channel_id: String
            let p_pinned: Bool
        }
        try await client
            .rpc("chat_set_channel_pinned",
                 params: Params(p_channel_id: channelId.uuidString,
                                p_pinned: pinned))
            .execute()
    }

    // MARK: - Global FTS search

    public func searchMessages(query: String, limit: Int = 50) async throws -> [ChatMessage] {
        struct Params: Encodable {
            let p_query: String
            let p_limit: Int
        }
        let rows: [ChatMessage] = try await client
            .rpc("chat_search_messages",
                 params: Params(p_query: query, p_limit: limit))
            .execute()
            .value
        return rows
    }
}

// MARK: - Mute presets

public enum MutePreset: String, CaseIterable, Identifiable {
    case oneHour, eightHours, untilTomorrowMorning, forever

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .oneHour:               return "1 小时"
        case .eightHours:             return "8 小时"
        case .untilTomorrowMorning:  return "明早"
        case .forever:                return "永久"
        }
    }

    /// Resolves the preset to an absolute timestamp. `forever` returns a
    /// far-future date (year 9999) — server compares with `> now()` so this
    /// reads as "always muted".
    public func resolve(now: Date = Date()) -> Date {
        let cal = Calendar.current
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .eightHours:
            return now.addingTimeInterval(8 * 3600)
        case .untilTomorrowMorning:
            // 明早 = 第二天 08:00 (local time)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = 8
            comps.minute = 0
            return cal.date(from: comps) ?? now.addingTimeInterval(8 * 3600)
        case .forever:
            // 永远 = 9999-12-31。Postgres timestamptz 能存到 294276 AD,无溢出。
            var comps = DateComponents()
            comps.year = 9999
            comps.month = 12
            comps.day = 31
            return cal.date(from: comps) ?? now.addingTimeInterval(100 * 365 * 86400)
        }
    }
}
