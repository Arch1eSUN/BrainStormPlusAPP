import Foundation
import Combine
import CoreMotion
import SwiftUI

// ══════════════════════════════════════════════════════════════════
// BsMotionManager —— CoreMotion 轻量包装（设备倾斜发布器）
//
// 为 Attendance 签到模块的 "液态填充签名动画"（Signature A）提供
// 设备左右倾斜信号。详见 docs/plans/2026-04-24-ios-full-redesign-plan.md
// §2.6 Signature A。
//
// 生命周期契约（MUST 严格遵守，防止电池损耗）：
//   • 绝不在 init() 里自动 start()；生命周期交给 SwiftUI 视图：
//       .onAppear  { if !reduceMotion && !ProcessInfo.processInfo
//                     .isLowPowerModeEnabled { motion.start() } }
//       .onDisappear { motion.stop() }
//   • Reduce Motion / Low Power Mode 的判定写在 视图 层（env），
//     不在这里；本类只管启停和低通滤波。
//   • deinit 中无条件 stop，作为兜底防泄漏。
//
// 性能约束：
//   • 更新频率 1/30 s（30 Hz）够用；不要飙到 60 Hz（耗电）。
//   • 回调在后台 OperationQueue 上触发，再 hop 回 @MainActor 去
//     写 @Published —— 绝不能在主线程上做 startDeviceMotionUpdates。
//   • 低通滤波 α = 0.85，抑制抖动但保持跟手。
//
// Swift 6 并发提示：
//   • 类本身不标 @MainActor —— `ObservableObject` 的协议要求在
//     nonisolated 上下文下可见，@MainActor 类会破坏 conformance。
//   • `start() / stop()` 分别显式标 @MainActor，因为它们要触发
//     @Published 变更（必须主线）。
//   • 回调把原始样本 hop 到 @MainActor 再写入 tiltX。
// ══════════════════════════════════════════════════════════════════

public final class BsMotionManager: ObservableObject {
    /// Tilt around the Y axis (left/right), normalized to [-1, 1].
    /// 0 = flat. Positive = tilted right. Smoothed with low-pass filter.
    @Published public private(set) var tiltX: CGFloat = 0

    /// Whether manager is currently polling.
    @Published public private(set) var isActive: Bool = false

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    /// Low-pass filter alpha. 0 = no smoothing (jittery), 1 = frozen. 0.85 is a good default.
    private let smoothing: CGFloat = 0.85

    /// Update interval — 1/30 s is enough for visual tilt; don't go to 60 Hz (battery cost).
    private let updateInterval: TimeInterval = 1.0 / 30

    public init() {
        queue.name = "com.brainstorm.motion"
        queue.qualityOfService = .userInitiated
    }

    /// Start polling IF allowed by OS (not Low Power, not Reduce Motion).
    /// Caller is responsible for checking those before calling start().
    @MainActor
    public func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !isActive else { return }
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            // gravity.x in [-1, 1] — negative = tilted left
            let raw = CGFloat(data.gravity.x)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Low-pass filter
                self.tiltX = self.tiltX * self.smoothing + raw * (1 - self.smoothing)
            }
        }
        isActive = true
    }

    /// Stop polling. MUST be called on view disappear to save battery.
    @MainActor
    public func stop() {
        guard isActive else { return }
        motionManager.stopDeviceMotionUpdates()
        tiltX = 0
        isActive = false
    }

    deinit {
        // deinit 是 nonisolated；CMMotionManager.stopDeviceMotionUpdates 可在任意队列调用。
        motionManager.stopDeviceMotionUpdates()
    }
}

// ──────────────────────────────────────────────────────────────────
// Preview —— 模拟器上 tiltX 保持 0，真机上随设备旋转变化
// ──────────────────────────────────────────────────────────────────

#Preview {
    struct P: View {
        @StateObject private var manager = BsMotionManager()
        var body: some View {
            VStack(spacing: 20) {
                Text("Is active: \(manager.isActive ? "yes" : "no")")
                Text(String(format: "tiltX: %.3f", manager.tiltX))
                    .monospacedDigit()
            }
            .onAppear { manager.start() }
            .onDisappear { manager.stop() }
        }
    }
    return P()
}
