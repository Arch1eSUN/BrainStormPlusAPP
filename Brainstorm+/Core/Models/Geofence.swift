import Foundation

public struct Geofence: Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public var lat: Double?
    public var lng: Double?
    public var radius: Int
    public var address: String

    public init(
        id: String = UUID().uuidString,
        name: String = "新办公区",
        lat: Double? = nil,
        lng: Double? = nil,
        radius: Int = 300,
        address: String = ""
    ) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radius = radius
        self.address = address
    }

    public var isValid: Bool {
        lat != nil && lng != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
