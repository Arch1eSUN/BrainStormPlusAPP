import SwiftUI

/// Emulates the Web's magnetic pointer interaction. 
/// In iOS, this translates to tracking the user's drag gesture over the button.
public struct ZYMagneticButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    
    @State private var offset = CGSize.zero
    @State private var isPressed = false
    
    // Configurable spring for the "snap back" effect
    private let magneticSpring = Animation.interactiveSpring(
        response: 0.3,
        dampingFraction: 0.5,
        blendDuration: 0.2
    )
    
    public init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }
    
    public var body: some View {
        Button(action: {
            HapticManager.shared.trigger(.light)
            action()
        }) {
            label()
        }
        .buttonStyle(MagneticButtonStyle(offset: offset, isPressed: isPressed))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        HapticManager.shared.trigger(.soft)
                    }
                    
                    // Cap the magnetic pull distance
                    let maxTranslation: CGFloat = 16
                    let translationX = max(min(value.translation.width * 0.3, maxTranslation), -maxTranslation)
                    let translationY = max(min(value.translation.height * 0.3, maxTranslation), -maxTranslation)
                    
                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.8)) {
                        offset = CGSize(width: translationX, height: translationY)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    HapticManager.shared.trigger(.rigid)
                    
                    withAnimation(magneticSpring) {
                        offset = .zero
                    }
                }
        )
    }
}

/// Internal style to combine the Squishy effect with the Magnetic displacement
private struct MagneticButtonStyle: ButtonStyle {
    var offset: CGSize
    var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(offset)
            .scaleEffect(isPressed || configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
