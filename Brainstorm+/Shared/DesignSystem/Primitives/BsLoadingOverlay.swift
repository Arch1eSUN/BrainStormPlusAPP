import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsLoadingOverlay —— 统一"保存中 / 提交中"遮罩
//
// 设计来源：audit 发现 7 个 submit sheet 都有同款 overlay 代码：
//   ZStack { Color.black.opacity(0.25); ProgressView(); }.cornerRadius(12)
// 现在抽成单 modifier / View，统一外观 + 加 `.interactiveDismissDisabled`
// 兜底（用户在保存中往下拖 sheet 不应关闭），并走 BsColor.ink 而不是
// 原始 Color.black。
//
// 用法：
//   ContentView()
//     .bsLoadingOverlay(
//       isLoading: viewModel.isSaving,
//       label: "提交中…"
//     )
//
// 特性：
//   • 自动 `.interactiveDismissDisabled(isLoading)` 锁 sheet 下滑
//   • dim scrim 走 BsColor.ink.opacity(0.25)，深色模式自动调色
//   • ProgressView 白 tint（对比 scrim）
//   • 可选 label 文字（提交中 / 保存中 / 生成中）
//   • iOS 26 ultraThinMaterial 作 pill 背板
// ══════════════════════════════════════════════════════════════════

public struct BsLoadingOverlay: ViewModifier {
    let isLoading: Bool
    let label: String?

    public init(isLoading: Bool, label: String? = nil) {
        self.isLoading = isLoading
        self.label = label
    }

    public func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isLoading)
            .overlay {
                if isLoading {
                    ZStack {
                        BsColor.ink.opacity(0.25)
                            .ignoresSafeArea()

                        VStack(spacing: BsSpacing.md) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            if let label, !label.isEmpty {
                                Text(label)
                                    .font(BsTypography.bodyMedium)
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, BsSpacing.xl)
                        .padding(.vertical, BsSpacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
            .animation(BsMotion.Anim.smooth, value: isLoading)
    }
}

public extension View {
    /// 统一保存 / 提交 / 生成 loading overlay。
    /// 会自动 `.interactiveDismissDisabled(isLoading)` 锁 sheet 下滑，防止用户误关。
    func bsLoadingOverlay(isLoading: Bool, label: String? = nil) -> some View {
        modifier(BsLoadingOverlay(isLoading: isLoading, label: label))
    }
}

#Preview {
    struct P: View {
        @State private var loading = true
        var body: some View {
            ZStack { BsColor.pageBackground.ignoresSafeArea() }
                .frame(width: 320, height: 480)
                .bsLoadingOverlay(isLoading: loading, label: "提交中…")
                .onTapGesture { loading.toggle() }
        }
    }
    return P()
}
