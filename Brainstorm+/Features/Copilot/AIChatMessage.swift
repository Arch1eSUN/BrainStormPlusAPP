import Foundation
import Combine

public struct AIChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: String // "user" or "assistant"
    public var content: String
    
    public init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}
