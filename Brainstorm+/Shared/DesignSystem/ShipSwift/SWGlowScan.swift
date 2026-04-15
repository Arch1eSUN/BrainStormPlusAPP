import SwiftUI

public struct SWGlowScan: ViewModifier {
    @State private var hoverPoint: CGFloat = -0.5
    
    var color: Color
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, color.opacity(0.8), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(proxy.size.height * 0.4, 40))
                        .offset(y: proxy.size.height * hoverPoint)
                        .blendMode(.screen)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 2.5)
                        .repeatForever(autoreverses: false)
                ) {
                    hoverPoint = 1.5
                }
            }
    }
}

public extension View {
    func glowScan(color: Color = .white) -> some View {
        self.modifier(SWGlowScan(color: color))
    }
}
