// ═══════════════════════════════════════════════════════════════════════════
// LiquidFillShape.swift
// BrainStorm+ · Shared/DesignSystem/Primitives
//
// A SwiftUI Shape that draws a liquid fill inside a rounded rectangle frame
// (used by the Attendance hero card). The fill height represents today's
// worked-hours progress (0 → 1 against an 8h day). An animated sine-wave
// ripples across the surface, and a gyroscope tilt skews the waterline so
// the liquid appears to slosh as the device rotates.
//
// Usage: overlay inside `BsHeroCard`, clipped by the card's corner radius.
// Caller animates `phase` via `TimelineView(.animation)` and supplies
// `tiltX` from `MotionManager`. For Reduce Motion, pass `amplitude = 0`.
//
// Reference: docs/plans/2026-04-24-ios-full-redesign-plan.md §2.6
//            (Signature A — Liquid Attendance Fill)
// Imports:   SwiftUI only. CoreMotion lives in MotionManager.
// ═══════════════════════════════════════════════════════════════════════════

import SwiftUI

// ─── Liquid surface math (shared) ─────────────────────────────────────
// Extracted so both LiquidFillShape（body）和 LiquidSurfaceLineShape（高光线）
// 走同一套数学，两个 Shape 完全同步。
//
// 3-wave 叠加：频率比 1 : 2.3 : 4.7（非整数）
//            速度比 1.0 : 1.45 : 2.1
//            相位偏置 0 / 1.1 / 0.7 rad
//            振幅权重 0.7 / 0.4 / 0.2
@inline(__always)
internal func _liquidSurfaceY(
    atNormalizedX x: CGFloat,
    baseY: CGFloat,
    tiltMag: CGFloat,
    phase: CGFloat,
    amplitude: CGFloat,
    frequency: CGFloat
) -> CGFloat {
    let twoPi = CGFloat.pi * 2
    let xRad = x * twoPi
    // Wave 3 振幅降到 0.08 —— 高频微扰只作底层 texture，不再贡献可见波峰
    // （原 0.2 在 80 采样下每周期 ~5.7 点，linear 插值下成锯齿噪点）
    let w1 = sin(phase * 1.0  + xRad * frequency * 1.0) * (amplitude * 0.72)
    let w2 = sin(phase * 1.45 + xRad * frequency * 2.3 + 1.1) * (amplitude * 0.32)
    let w3 = sin(phase * 2.1  + xRad * frequency * 4.7 + 0.7) * (amplitude * 0.08)
    let tiltDelta = (x - 0.5) * 2 * tiltMag
    return baseY + w1 + w2 + w3 + tiltDelta
}

// Catmull-Rom spline helper —— 穿过所有采样点的 C1 连续三次贝塞尔曲线。
// 4 点组 (p0,p1,p2,p3) 决定从 p1 到 p2 的弧段，控制点：
//     c1 = p1 + (p2 - p0) / 6
//     c2 = p2 - (p3 - p1) / 6
// 端点用"反射"扩展：p0 = p1 - (p2 - p1), p3 = p2 + (p2 - p1)
// 结果曲线无尖角、无折线，真正流体感。
@inline(__always)
internal func _appendSmoothCurve(through points: [CGPoint], into path: inout Path) {
    guard points.count >= 2 else { return }
    for i in 0..<(points.count - 1) {
        let p1 = points[i]
        let p2 = points[i + 1]
        let p0 = i > 0 ? points[i - 1] : CGPoint(x: 2 * p1.x - p2.x, y: 2 * p1.y - p2.y)
        let p3 = i < points.count - 2
            ? points[i + 2]
            : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)

        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
}

public struct LiquidFillShape: Shape {

    // MARK: - Inputs

    /// Fill height 0...1 (0 = empty, 1 = full). Clamped internally.
    public var progress: CGFloat

    /// Wave phase in radians — caller animates this via TimelineView.
    public var phase: CGFloat

    /// Gyroscope tilt X component (-1 … 1 from MotionManager). 0 = no tilt.
    public var tiltX: CGFloat

    /// Wave amplitude in points. Default 4. Reduce Motion → pass 0.
    public var amplitude: CGFloat

    /// Wave frequency (number of crests across width). Default 1.5.
    public var frequency: CGFloat

    // MARK: - Init

    public init(
        progress: CGFloat,
        phase: CGFloat = 0,
        tiltX: CGFloat = 0,
        amplitude: CGFloat = 4,
        frequency: CGFloat = 1.5
    ) {
        self.progress = progress
        self.phase = phase
        self.tiltX = tiltX
        self.amplitude = amplitude
        self.frequency = frequency
    }

    // MARK: - Animatable Data
    //
    // Pack (progress, phase, tiltX) so SwiftUI can interpolate all three
    // when the shape is driven by `.animation(...)` modifiers.

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(phase, tiltX)) }
        set {
            progress = newValue.first
            phase = newValue.second.first
            tiltX = newValue.second.second
        }
    }

    // MARK: - Path
    //
    // 真流体表面 ≠ 单 sine 波。真流体表面是**多个不同波长/相位/速度的行进波
    // 的线性叠加**（海洋学 Stokes / Pierson-Moskowitz 谱的简化形式）。
    // 单 sine 看起来像机械振荡；3 波以上且频率比不是整数时，表面呈现非周期
    // 扰动，人眼判断成"真实液体"。
    //
    // 参数选择：
    //   • 3 个 sine 成分：base / medium / ripple
    //   • 频率比 1 : 2.3 : 4.7 —— 不是整数比，避免合成波回到相同模式
    //   • 速度（phase 乘子）1.0 / 1.45 / 2.1 —— 不同速度制造 beat 起伏
    //   • 相位偏置 0 / 1.1rad / 0.7rad —— 进一步去对称
    //   • 振幅分配 0.7 / 0.4 / 0.2 —— 总和接近 1.0 * amplitude，不会爆幅

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let progressClamped = max(0, min(1, progress))
        guard rect.width > 0 else { return path }

        let baseY = rect.maxY - (rect.height * progressClamped)
        let tiltMag = tiltX * amplitude * 3
        let sampleCount: CGFloat = 80
        let step = rect.width / sampleCount

        var surfacePoints: [CGPoint] = []
        surfacePoints.reserveCapacity(Int(sampleCount) + 2)

        for x in stride(from: CGFloat(0), through: rect.width, by: step) {
            let normalizedX = x / rect.width
            let y = _liquidSurfaceY(atNormalizedX: normalizedX, baseY: baseY, tiltMag: tiltMag,
                                    phase: phase, amplitude: amplitude, frequency: frequency)
            surfacePoints.append(CGPoint(x: rect.minX + x, y: y))
        }
        if let last = surfacePoints.last, last.x < rect.maxX {
            let y = _liquidSurfaceY(atNormalizedX: 1.0, baseY: baseY, tiltMag: tiltMag,
                                    phase: phase, amplitude: amplitude, frequency: frequency)
            surfacePoints.append(CGPoint(x: rect.maxX, y: y))
        }

        guard let first = surfacePoints.first else { return path }
        path.move(to: first)
        // Catmull-Rom 三次贝塞尔穿过所有采样点（替代 addLine 折线段，消除锯齿）
        _appendSmoothCurve(through: surfacePoints, into: &path)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LiquidSurfaceLineShape —— 只绘制液面顶部曲线（不闭合），供 stroke 高光用。
// 和 LiquidFillShape 共用 _liquidSurfaceY 保证形状完全同步。
// ═══════════════════════════════════════════════════════════════════════════

public struct LiquidSurfaceLineShape: Shape {
    public var progress: CGFloat
    public var phase: CGFloat
    public var tiltX: CGFloat
    public var amplitude: CGFloat
    public var frequency: CGFloat

    public init(
        progress: CGFloat,
        phase: CGFloat = 0,
        tiltX: CGFloat = 0,
        amplitude: CGFloat = 12,
        frequency: CGFloat = 1.6
    ) {
        self.progress = progress
        self.phase = phase
        self.tiltX = tiltX
        self.amplitude = amplitude
        self.frequency = frequency
    }

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(phase, tiltX)) }
        set {
            progress = newValue.first
            phase = newValue.second.first
            tiltX = newValue.second.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let progressClamped = max(0, min(1, progress))
        guard rect.width > 0 else { return path }

        let baseY = rect.maxY - (rect.height * progressClamped)
        let tiltMag = tiltX * amplitude * 3
        let sampleCount: CGFloat = 80
        let step = rect.width / sampleCount

        var points: [CGPoint] = []
        points.reserveCapacity(Int(sampleCount) + 2)
        for x in stride(from: CGFloat(0), through: rect.width, by: step) {
            let normalizedX = x / rect.width
            let y = _liquidSurfaceY(atNormalizedX: normalizedX, baseY: baseY, tiltMag: tiltMag,
                                    phase: phase, amplitude: amplitude, frequency: frequency)
            points.append(CGPoint(x: rect.minX + x, y: y))
        }
        if let last = points.last, last.x < rect.maxX {
            let y = _liquidSurfaceY(atNormalizedX: 1.0, baseY: baseY, tiltMag: tiltMag,
                                    phase: phase, amplitude: amplitude, frequency: frequency)
            points.append(CGPoint(x: rect.maxX, y: y))
        }

        guard let first = points.first else { return path }
        path.move(to: first)
        // Catmull-Rom 三次贝塞尔穿过采样点（Shape 共享 helper）
        _appendSmoothCurve(through: points, into: &path)

        return path
    }
}

// MARK: - Preview

#Preview {
    struct P: View {
        @State private var progress: CGFloat = 0.5
        var body: some View {
            VStack(spacing: 20) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate) * 2
                    LiquidFillShape(progress: progress, phase: phase)
                        .fill(BsColor.brandAzure.opacity(0.35))
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                        )
                }
                Slider(value: $progress, in: 0...1)
                Text("Progress: \(progress, specifier: "%.2f")")
                    .font(.caption)
            }
            .padding()
        }
    }
    return P()
}
