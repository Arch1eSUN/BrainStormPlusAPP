import SwiftUI

/// Emulates the Web React Spotlight Card
/// Tracks a user's finger during a long press to reveal a glow behind the card.
public struct ZYSpotlightCard<Content: View>: View {
    let content: () -> Content
    
    @State private var location: CGPoint? = nil
    @State private var isPressing = false
    
    private let spotlightColor: Color = Color.Brand.primary.opacity(0.15)
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        content()
            .background(
                ZStack {
                    // Base background
                    Color.Brand.paper
                    
                    // Spotlight
                    if let location = location {
                        RadialGradient(
                            colors: [spotlightColor, .clear],
                            center: UnitPoint(x: location.x, y: location.y),
                            startRadius: 0,
                            endRadius: 150
                        )
                        .blendMode(.screen)
                    }
                }
            )
            .overlay(
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.8)) {
                                        location = CGPoint(
                                            x: value.location.x / proxy.size.width,
                                            y: value.location.y / proxy.size.height
                                        )
                                        isPressing = true
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.5)) {
                                        location = nil
                                        isPressing = false
                                    }
                                }
                        )
                }
            )
            .zyCardStyle()
            // Slight spatial lift effect while tracking
            .scaleEffect(isPressing ? 1.02 : 1.0)
            .shadow(color: isPressing ? Color.black.opacity(0.08) : Color.clear, radius: 20, y: 10)
    }
}
