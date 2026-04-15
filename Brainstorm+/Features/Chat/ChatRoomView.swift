import SwiftUI
import Combine

public struct ChatRoomView: View {
    public let channel: ChatChannel
    @State private var messageText: String = ""
    
    public init(channel: ChatChannel) {
        self.channel = channel
    }
    
    public var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Empty state for placeholder
                        Text("Beginning of conversation in \(channel.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                        
                        if let lastMessage = channel.lastMessage {
                            messageBubble(text: lastMessage, isCurrentUser: false)
                        }
                    }
                    .padding()
                }
                
                // Bottom Input Bar
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    
                    TextField("Type a message...", text: $messageText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Capsule())
                    
                    Button(action: {
                        // Send logic down the line
                        messageText = ""
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(messageText.isEmpty ? .gray : .blue)
                            .rotationEffect(.degrees(45))
                    }
                    .disabled(messageText.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.2)), alignment: .top)
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func messageBubble(text: String, isCurrentUser: Bool) -> some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 50) }
            
            Text(text)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isCurrentUser ? Color.blue : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isCurrentUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            if !isCurrentUser { Spacer(minLength: 50) }
        }
    }
}
