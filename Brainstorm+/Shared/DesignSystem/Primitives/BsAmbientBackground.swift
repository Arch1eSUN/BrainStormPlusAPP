import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsAmbientBackground —— Phase 22: 弥散彻底退出
//
// 五人评审合议 + 用户明确指令：**彻底放弃弥散，专注流体**。
// 本 primitive 保留 API 兼容（调用方不用改），但**始终渲染纯净 pageBackground**，
// 所有 blob / opacity / intensity / coral 参数一律忽略。
//
// 如果后面某个签名瞬间要再启弥散（login / 打卡成功 ripple / 庆祝），
// 用局部 RadialGradient 手搓或专用 primitive，不走这个。
// ══════════════════════════════════════════════════════════════════

public struct BsAmbientBackground: View {
    /// 保留参数仅为 API 兼容，**当前版本全部忽略**。
    public init(intensity: CGFloat = 0.0, includeCoral: Bool = false) {
        _ = intensity
        _ = includeCoral
    }

    public var body: some View {
        BsColor.pageBackground.ignoresSafeArea()
    }
}
