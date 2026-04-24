import SwiftUI

/// Legacy card style —— v1.1 redesign 之后对齐 `BsContentCard` 的 matte 材质
/// (surfacePrimary fill + hairline stroke + light shadow)。
///
/// 所有现存 `.modifier(ZYCardStyleModifier())` 和 `.zyCardStyle()` 调用保持
/// 不变；内部不再依赖已废弃的旧玻璃 modifier，改为直接渲染 matte 卡壳。
/// cornerRadius / shadowRadius / shadowY 参数保留以兼容调用签名（shadow 参数
/// 现在走 BsShadow.contentCard 统一值，仅 light mode 生效）。
public struct ZYCardStyleModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = BsRadius.xl, shadowRadius: CGFloat = 32, shadowY: CGFloat = 8) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(BsColor.surfacePrimary)
            .clipShape(shape)
            .overlay(shape.stroke(BsColor.borderSubtle, lineWidth: 0.5))
            .bsShadow(colorScheme == .dark ? BsShadow.none : BsShadow.contentCard)
    }
}

public extension View {
    /// 便捷 alias，等价于 `.modifier(ZYCardStyleModifier())`。
    func zyCardStyle(cornerRadius: CGFloat = BsRadius.xl) -> some View {
        modifier(ZYCardStyleModifier(cornerRadius: cornerRadius))
    }
}
