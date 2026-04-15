import Foundation
import Supabase

public enum AIError: Swift.Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid endpoint URL"
        case .unauthorized: return "Session expired. Please re-login."
        case .serverError(let msg): return msg
        }
    }
}

public class AICopilotService {
    // DEV Backend URL (iOS Simulator connects to localhost via 127.0.0.1)
    private let apiURL = URL(string: "http://127.0.0.1:3000/api/chat")!
    
    public init() {}
    
    public func streamChat(messages: [AIChatMessage]) async throws -> AsyncThrowingStream<String, Error> {
        let session = try await supabase.auth.session
        let token = session.accessToken
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct LeanMessage: Codable { let role: String; let content: String }
        struct LeanRequest: Codable { let messages: [LeanMessage] }
        
        let payload = LeanRequest(messages: messages.map { LeanMessage(role: $0.role, content: $0.content) })
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.serverError("Bad Response")
        }
        
        if httpResponse.statusCode == 401 { throw AIError.unauthorized }
        guard httpResponse.statusCode == 200 else {
            throw AIError.serverError("Status Code: \(httpResponse.statusCode)")
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await character in bytes.characters {
                        continuation.yield(String(character))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
