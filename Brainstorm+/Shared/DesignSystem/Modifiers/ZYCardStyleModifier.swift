import SwiftUI

/// Applies the double-bezel premium card effect derived from BrainStorm+ web design tokens.
public struct ZYCardStyleModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat
    
    public init(cornerRadius: CGFloat = 24, shadowRadius: CGFloat = 10, shadowY: CGFloat = 4) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }
    
    public func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Outer shadow for floating feel
            .shadow(color: Color.black.opacity(0.03), radius: shadowRadius, y: shadowY)
            // Inner/border stroke overlay acting as the "double bezel" white trim reflection
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            // Optional second ring overlay to create an inset highlight feel
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.8), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing), lineWidth: 0.5)
            )
    }
}
