import SwiftUI

/// Shimmer effect modifier for Skeleton loading views
public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.04), // soft shimmer color
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: proxy.size.width * 2)
                    .offset(x: proxy.size.width * phase)
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
