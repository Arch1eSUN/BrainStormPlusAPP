import SwiftUI

/// Tactile push animation for buttons (Pro-max UX Guideline)
public struct SquishyButtonStyle: ButtonStyle {
    var scaleScale: CGFloat
    
    public init(scaleScale: CGFloat = 0.96) {
        self.scaleScale = scaleScale
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleScale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(BsMotion.Anim.overshoot, value: configuration.isPressed)
    }
}
