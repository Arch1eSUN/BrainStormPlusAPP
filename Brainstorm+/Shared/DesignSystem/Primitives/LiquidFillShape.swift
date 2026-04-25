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
//
// ─── v1.3.2 perf rewrite (2026-04-25) ──────────────────────────────────────
// 之前 v1.3.1 把 TimelineView 拉到 30Hz 减负荷，方向错了。用户要的是流畅+精美，
// 不是省电。本次重写：
//
//   1. sin lookup table (256 entries)   — 替代 Foundation.sin()，5–10× 快
//   2. wave 数 3 → 2                    — 高频微扰 (w3) 视觉无感，砍掉
//   3. sample 数 80 → 60                — 60+ 后人眼对密度无感
//   4. addCurve(Catmull-Rom) →          — 控制点少一次乘法 / 段
//      addQuadCurve(midpoint smoothing)
//
// 数学验证：
//   旧 cost = 80 sample × 3 wave × 4 shape × 30 fps = 28,800 sin/s
//   新 cost = 60 sample × 2 wave × 4 shape × 60 fps = 28,800 lookup/s
//             ≈ 5× 加速（lookup ~1ns vs sin ~5–10ns）
//   每帧 path build ≈ 60 segment × 4 shape ≈ 240 quad curve / frame，
//   远低于 16.6ms (60Hz) 预算。
// ═══════════════════════════════════════════════════════════════════════════

import SwiftUI
import Darwin // for sin() during table init

// ─── Sin lookup table ────────────────────────────────────────────────────
// 256 entries cover [0, 2π). Linear interp between adjacent entries gives
// ~0.012% max error vs Foundation.sin —— 远低于人眼阈值。
//
// 每帧调用 ~480 次（60 sample × 2 wave × 4 shape）→ 一次 lookup ~1ns 远快
// 于一次 sin() ~5-10ns。GPU 最终绘制成本不变，CPU path build 时间砍 5-10×。
//
// 注：声明为 `@usableFromInline let` 让 inline 函数能跨模块访问。
@usableFromInline
internal let _sinLUT: [CGFloat] = {
    let count = 256
    var table = [CGFloat](repeating: 0, count: count + 1)  // +1 for guard
    for i in 0...count {
        let theta = Double(i) / Double(count) * 2.0 * .pi
        table[i] = CGFloat(Darwin.sin(theta))
    }
    return table
}()

@inline(__always)
@usableFromInline
internal func _fastSin(_ x: CGFloat) -> CGFloat {
    // Wrap to [0, 2π)
    let twoPi = CGFloat.pi * 2
    var t = x.truncatingRemainder(dividingBy: twoPi)
    if t < 0 { t += twoPi }
    // Map to [0, 256)
    let pos = t / twoPi * 256.0
    let idx = Int(pos)
    let frac = pos - CGFloat(idx)
    let a = _sinLUT[idx]
    let b = _sinLUT[idx + 1]  // safe: table has 257 entries
    return a + (b - a) * frac
}

// ─── Liquid surface math (shared) ─────────────────────────────────────
// Extracted so both LiquidFillShape (body) 和 LiquidSurfaceLineShape (高光线)
// 走同一套数学，两个 Shape 完全同步。
//
// v1.3.2: 2-wave 叠加（原 3-wave 第三层是 0.08*amp 高频微扰，60-sample 下
//          每周期采样数已不足 Nyquist 限，肉眼看不到，纯粹浪费 CPU）：
//            频率比 1 : 2.3（非整数 → 防止合成波回到相同模式）
//            速度比 1.0 : 1.45
//            相位偏置 0 / 1.1 rad
//            振幅权重 0.78 / 0.32（总和 ~1.1*amp，略增主波保留视觉冲击）
@inline(__always)
@usableFromInline
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
    let w1 = _fastSin(phase * 1.0  + xRad * frequency * 1.0) * (amplitude * 0.78)
    let w2 = _fastSin(phase * 1.45 + xRad * frequency * 2.3 + 1.1) * (amplitude * 0.32)
    let tiltDelta = (x - 0.5) * 2 * tiltMag
    return baseY + w1 + w2 + tiltDelta
}

// Quadratic-curve mid-point smoothing —— 比 Catmull-Rom 三次贝塞尔每段
// 少 1 次控制点构造（Catmull-Rom 每段算 c1/c2 各 4 次乘法 + 4 次减法；
// quad-mid 每段只算 1 次中点）。视觉上在 60+ sample 密度下几乎无差别。
//
// 算法：把每对相邻采样点之间用 quad curve 连接，控制点取上一采样点，
//      终点取相邻两点的中点。最后一段终点用最后一个采样点。
@inline(__always)
@usableFromInline
internal func _appendSmoothCurve(through points: [CGPoint], into path: inout Path) {
    guard points.count >= 2 else { return }
    if points.count == 2 {
        path.addLine(to: points[1])
        return
    }
    // Path 已 move(to: points[0])，从 points[1] 开始用 quad curve
    for i in 1..<(points.count - 1) {
        let p1 = points[i]
        let p2 = points[i + 1]
        let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        path.addQuadCurve(to: mid, control: p1)
    }
    // 最后一段 line 到端点（保证端点精确）
    path.addLine(to: points[points.count - 1])
}

// ─── Path build helper（DRY for fill + line shapes）────────────────────
// 抽出避免 LiquidFillShape 和 LiquidSurfaceLineShape 重复同样的 surfacePoints
// 构造代码。两个 Shape 在 SwiftUI 中是独立 path()，但样本生成逻辑完全一致。
@inline(__always)
@usableFromInline
internal func _buildSurfacePoints(
    rect: CGRect,
    progressClamped: CGFloat,
    phase: CGFloat,
    tiltX: CGFloat,
    amplitude: CGFloat,
    frequency: CGFloat,
    sampleCount: Int = 60
) -> [CGPoint] {
    let baseY = rect.maxY - (rect.height * progressClamped)
    let tiltMag = tiltX * amplitude * 3
    let stepX = rect.width / CGFloat(sampleCount)

    var points: [CGPoint] = []
    points.reserveCapacity(sampleCount + 2)

    for i in 0...sampleCount {
        let x = CGFloat(i) * stepX
        let normalizedX = x / rect.width
        let y = _liquidSurfaceY(
            atNormalizedX: normalizedX, baseY: baseY, tiltMag: tiltMag,
            phase: phase, amplitude: amplitude, frequency: frequency
        )
        points.append(CGPoint(x: rect.minX + x, y: y))
    }
    return points
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
    // 的线性叠加**。v1.3.2 用 2-wave（足够"非周期"且 60Hz 流畅），频率比
    // 1 : 2.3 非整数防止合成波回到相同模式。

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let progressClamped = max(0, min(1, progress))
        guard rect.width > 0 else { return path }

        let surfacePoints = _buildSurfacePoints(
            rect: rect,
            progressClamped: progressClamped,
            phase: phase,
            tiltX: tiltX,
            amplitude: amplitude,
            frequency: frequency
        )

        guard let first = surfacePoints.first else { return path }
        path.move(to: first)
        _appendSmoothCurve(through: surfacePoints, into: &path)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LiquidSurfaceLineShape —— 只绘制液面顶部曲线（不闭合），供 stroke 高光用。
// 和 LiquidFillShape 共用 _liquidSurfaceY / _buildSurfacePoints 保证形状完全同步。
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

        let points = _buildSurfacePoints(
            rect: rect,
            progressClamped: progressClamped,
            phase: phase,
            tiltX: tiltX,
            amplitude: amplitude,
            frequency: frequency
        )

        guard let first = points.first else { return path }
        path.move(to: first)
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
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
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
