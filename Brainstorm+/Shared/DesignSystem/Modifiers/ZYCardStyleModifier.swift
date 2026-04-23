import SwiftUI

/// Legacy card style — 代理到 BsGlassCard，从"实心白卡 + hairline"升级为
/// Web DNA 招牌玻璃卡（.glassEffect + inset 1px 顶高光 + 软 drop shadow）。
///
/// 所有现存 `.modifier(ZYCardStyleModifier())` 调用自动升级到 glass 材质，
/// 不用改业务代码。cornerRadius 参数保留以兼容调用签名。
public struct ZYCardStyleModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    public init(cornerRadius: CGFloat = BsRadius.xl, shadowRadius: CGFloat = 32, shadowY: CGFloat = 8) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        content.bsGlassCard(cornerRadius: cornerRadius)
    }
}

public extension View {
    /// 便捷 alias，等价于 `.modifier(ZYCardStyleModifier())`。
    func zyCardStyle(cornerRadius: CGFloat = BsRadius.xl) -> some View {
        modifier(ZYCardStyleModifier(cornerRadius: cornerRadius))
    }
}
