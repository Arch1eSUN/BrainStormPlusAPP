import SwiftUI

/// Emulates the Web Tactile deeply transparent backgrounds matching `--color-surface-card`
public struct ZYGlassBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    var blurRadius: CGFloat
    
    public init(cornerRadius: CGFloat = 20, opacity: Double = 0.4, blurRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blurRadius = blurRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.Brand.paper.opacity(opacity) // Base paper transparency
                    .background(.ultraThinMaterial)   // iOS native ultra thin glass
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}
