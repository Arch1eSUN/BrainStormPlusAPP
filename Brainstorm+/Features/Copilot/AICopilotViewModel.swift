import Foundation
import Combine

@MainActor
public class AICopilotViewModel: ObservableObject {
    @Published public var messages: [AIChatMessage] = []
    @Published public var inputMessage: String = ""
    @Published public var isTyping: Bool = false
    @Published public var errorStatus: String?
    
    private let service: AICopilotService
    private var bag = Set<AnyCancellable>()
    
    public init(service: AICopilotService = AICopilotService()) {
        self.service = service
    }
    
    public func clearChat() {
        messages.removeAll()
        errorStatus = nil
    }
    
    public func sendMessage() {
        let text = inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Append user message
        let userMessage = AIChatMessage(role: "user", content: text)
        messages.append(userMessage)
        inputMessage = ""
        isTyping = true
        errorStatus = nil
        
        let context = messages // Capture current messages
        
        Task {
            do {
                let stream = try await service.streamChat(messages: context)
                
                // Add empty assistant message placeholder
                let index = self.messages.count
                self.messages.append(AIChatMessage(role: "assistant", content: ""))
                
                // Read chunks and append
                for try await fragment in stream {
                    self.messages[index].content += fragment
                }
                
                self.isTyping = false
            } catch {
                self.isTyping = false
                self.errorStatus = error.localizedDescription
                print("Copilot Stream Error: \(error)")
            }
        }
    }
}
