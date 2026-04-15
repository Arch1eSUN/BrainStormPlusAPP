import SwiftUI
import Combine

public struct AICopilotView: View {
    @StateObject private var viewModel = AICopilotViewModel()
    @FocusState private var isFocused: Bool
    
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }
                        
                        if viewModel.isTyping {
                            HStack {
                                ProgressView()
                                    .padding(8)
                                Spacer()
                            }
                            .id("typing")
                        }
                        
                        if let error = viewModel.errorStatus {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            chatInput
        }
        .background(Color.Brand.background)
        .navigationTitle("AI Copilot")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var header: some View {
        HStack {
            Text("BrainStorm AI")
                .font(.headline)
            Spacer()
            Button("Clear") { viewModel.clearChat() }
        }
        .padding()
        .background(Color.Brand.paper)
    }
    
    private func chatBubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer() }
            
            Text(message.content)
                .padding()
                .background(message.role == "user" ? Color.Brand.primary : Color.Brand.paper)
                .foregroundColor(message.role == "user" ? .white : Color.Brand.text)
                .cornerRadius(12)
            
            if message.role != "user" { Spacer() }
        }
    }
    
    private var chatInput: some View {
        HStack {
            TextField("Ask Copilot...", text: $viewModel.inputMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { viewModel.sendMessage() }
            
            Button(action: viewModel.sendMessage) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(Color.Brand.primary)
            }
            .disabled(viewModel.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color.Brand.paper)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isTyping {
            proxy.scrollTo("typing", anchor: .bottom)
        } else if let last = viewModel.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

struct AICopilotView_Previews: PreviewProvider {
    static var previews: some View {
        AICopilotView()
    }
}
