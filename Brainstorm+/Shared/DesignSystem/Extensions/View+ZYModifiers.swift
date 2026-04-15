import SwiftUI

public extension View {
    /// Applies the default BrainStorm+ Web iOS Card Style (spatial card shadows with double-bezel)
    func zyCardStyle(cornerRadius: CGFloat = 24, shadowRadius: CGFloat = 10, shadowY: CGFloat = 4) -> some View {
        self.modifier(ZYCardStyleModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowY: shadowY))
    }
    
    /// Applies ultra-thin glass material matching the Next.js spatial transparency aesthetic.
    func zyGlassBackground(cornerRadius: CGFloat = 20, opacity: Double = 0.4, blurRadius: CGFloat = 16) -> some View {
        self.modifier(ZYGlassBackgroundModifier(cornerRadius: cornerRadius, opacity: opacity, blurRadius: blurRadius))
    }
}
