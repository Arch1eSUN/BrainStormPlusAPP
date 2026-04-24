import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// ══════════════════════════════════════════════════════════════════
// Button Styles — ButtonStyle 协议封装
//
// 四种 style 对应四种按钮层级：
//   BsPrimary       → Ink 底白字，主 CTA（登录、保存、提交）
//   BsSecondary     → Azure 文字 + 透明底 + hairline，次要操作
//   BsDestructive   → Danger 红底白字，删除 / 退出
//   BsGhost         → 纯 Azure 文字 link 式
//
// 全部附带：
//   • press 时 scale 0.97 + opacity 0.85，spring 动画
//   • haptic medium on tap（loading 时不 trigger）
//   • full-width 默认，调用方可用 .fixedSize() 缩成 content-hugging
//   • size 参数控制垂直高度（medium 44 / large 52）
// ══════════════════════════════════════════════════════════════════

public enum BsButtonSize {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small:  return 36
        case .medium: return 48
        case .large:  return 52
        }
    }

    var font: Font {
        switch self {
        case .small:  return Font.custom("Inter-SemiBold", size: 13, relativeTo: .footnote)
        case .medium: return Font.custom("Inter-SemiBold", size: 15, relativeTo: .subheadline)
        case .large:  return Font.custom("Inter-SemiBold", size: 16, relativeTo: .callout)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:  return BsSpacing.md
        case .medium: return BsSpacing.lg
        case .large:  return BsSpacing.xl
        }
    }
}

// MARK: - Primary (Ink)

public struct BsPrimaryButtonStyle: ButtonStyle {
    var size: BsButtonSize = .medium
    var isLoading: Bool = false
    var fullWidth: Bool = true

    public init(size: BsButtonSize = .medium, isLoading: Bool = false, fullWidth: Bool = true) {
        self.size = size
        self.isLoading = isLoading
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: BsSpacing.sm) {
            if isLoading {
                ProgressView().tint(BsColor.buttonInkText)
            } else {
                configuration.label
            }
        }
        .font(size.font)
        .foregroundStyle(BsColor.buttonInkText)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: size.height)
        .padding(.horizontal, size.horizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md + 2, style: .continuous)
                .fill(BsColor.buttonInk)
        )
        .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
        .opacity(configuration.isPressed ? 0.90 : 1.0)
        .animation(BsMotion.Anim.overshoot, value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { Haptic.medium() }
        }
    }
}

// MARK: - Secondary (Azure outline)

public struct BsSecondaryButtonStyle: ButtonStyle {
    var size: BsButtonSize = .medium
    var fullWidth: Bool = true

    public init(size: BsButtonSize = .medium, fullWidth: Bool = true) {
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(BsColor.brandAzure)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md + 2, style: .continuous)
                    .fill(BsColor.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md + 2, style: .continuous)
                    .stroke(BsColor.borderDefault, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.light() }
            }
    }
}

// MARK: - Destructive

public struct BsDestructiveButtonStyle: ButtonStyle {
    var size: BsButtonSize = .medium
    var fullWidth: Bool = true

    public init(size: BsButtonSize = .medium, fullWidth: Bool = true) {
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md + 2, style: .continuous)
                    .fill(BsColor.danger)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.medium() }
            }
    }
}

// MARK: - Ghost (Azure text, 无底色)

public struct BsGhostButtonStyle: ButtonStyle {
    var size: BsButtonSize = .small

    public init(size: BsButtonSize = .small) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(BsColor.brandAzure)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(BsMotion.Anim.overshoot, value: configuration.isPressed)
    }
}

// ══════════════════════════════════════════════════════════════════
// Haptic 命名空间 — 函数式 API
// 跟 Samurai+ HapticManager 一致，避免 HapticManager.shared.trigger(.soft) 这种层级
// ══════════════════════════════════════════════════════════════════

public enum Haptic {
    public static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    public static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    public static func rigid() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }
    public static func soft() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    public static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    public static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
