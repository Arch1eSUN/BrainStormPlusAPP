import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsButton — iOS brand button primitive.
// Parity target: BrainStorm+-Web/src/design-system/brainstorm-plus/
// primitives/BsButton.variants.ts
//
// tone:  gradient (azure→mint, default for primary CTA)
//        azure   (solid brand blue)
//        mint    (solid brand cyan on ink text)
//        ink     (solid near-black — used by the login submit
//                 matching Web `bg-zy-ink`)
//        ghost   (transparent, uses muted surface on press)
//        danger  (solid red for destructive actions)
// size:  small / medium / large
// ══════════════════════════════════════════════════════════════════

public struct BsButton<Label: View>: View {
    public enum Tone {
        case gradient, azure, mint, ink, ghost, danger
    }

    public enum Size {
        case small, medium, large

        public var height: CGFloat {
            switch self {
            case .small:  return 36
            case .medium: return 44
            case .large:  return 52
            }
        }

        public var font: Font {
            switch self {
            case .small:  return Font.custom("Inter-SemiBold", size: 13, relativeTo: .footnote)
            case .medium: return Font.custom("Inter-SemiBold", size: 15, relativeTo: .subheadline)
            case .large:  return Font.custom("Inter-SemiBold", size: 16, relativeTo: .callout)
            }
        }

        public var horizontalPadding: CGFloat {
            switch self {
            case .small:  return BsSpacing.md
            case .medium: return BsSpacing.lg
            case .large:  return BsSpacing.xl
            }
        }
    }

    private let tone: Tone
    private let size: Size
    private let isLoading: Bool
    private let action: () -> Void
    private let label: Label

    public init(
        tone: Tone = .gradient,
        size: Size = .medium,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.tone = tone
        self.size = size
        self.isLoading = isLoading
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: BsSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .controlSize(.small)
                }
                label
                    .font(size.font)
                    .foregroundStyle(foregroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(backgroundLayer)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                // Ghost needs a hairline border to remain visible.
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(tone == .ghost ? BsColor.borderSubtle : Color.clear, lineWidth: 1)
            )
            .bsShadow(tone == .ghost ? BsShadow.none : BsShadow.sm)
        }
        .buttonStyle(SquishyButtonStyle())
        .disabled(isLoading)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch tone {
        case .gradient:
            LinearGradient(
                colors: [BsColor.brandAzure, BsColor.brandMint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .azure:
            BsColor.brandAzure
        case .mint:
            BsColor.brandMint
        case .ink:
            BsColor.ink
        case .ghost:
            Color.clear
        case .danger:
            BsColor.danger
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .gradient, .azure, .ink, .danger:
            return Color.white
        case .mint:
            return BsColor.ink
        case .ghost:
            return BsColor.ink
        }
    }
}
