import Foundation

/// Mirrors Web's `KeyResult` type in `BrainStorm+-Web/src/lib/actions/okr.ts:25-33`
/// and the `public.key_results` table (Web schema: `supabase/schema.sql:112-121`).
///
/// `target_value` / `current_value` are `NUMERIC` in Postgres so we model them
/// as `Double` to preserve fractional KRs (e.g. `3.5 / 10`). Web's UI coerces
/// them to `Number`, so the on-screen percentage is always integer-rounded.
public struct KeyResult: Identifiable, Codable, Hashable {
    public let id: UUID
    public let objectiveId: UUID
    public let title: String
    public let targetValue: Double
    public let currentValue: Double
    public let unit: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case objectiveId = "objective_id"
        case title
        case targetValue = "target_value"
        case currentValue = "current_value"
        case unit
        case createdAt = "created_at"
    }

    /// Custom decoder — Postgres `NUMERIC` can arrive as a JSON number OR a
    /// stringified number through PostgREST depending on precision; accept both.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.objectiveId = try c.decode(UUID.self, forKey: .objectiveId)
        self.title = try c.decode(String.self, forKey: .title)
        self.targetValue = try KeyResult.decodeNumeric(c, key: .targetValue) ?? 100
        self.currentValue = try KeyResult.decodeNumeric(c, key: .currentValue) ?? 0
        self.unit = try c.decodeIfPresent(String.self, forKey: .unit)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(objectiveId, forKey: .objectiveId)
        try c.encode(title, forKey: .title)
        try c.encode(targetValue, forKey: .targetValue)
        try c.encode(currentValue, forKey: .currentValue)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    private static func decodeNumeric(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Double? {
        if let d = try? container.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? container.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    // MARK: - Derived

    /// Integer-rounded percentage, capped at 100. Matches Web's
    /// `Math.min(Math.round((kr.current_value / kr.target_value) * 100), 100)`.
    public var progressPercent: Int {
        guard targetValue > 0 else { return 0 }
        return min(Int(((currentValue / targetValue) * 100).rounded()), 100)
    }
}
