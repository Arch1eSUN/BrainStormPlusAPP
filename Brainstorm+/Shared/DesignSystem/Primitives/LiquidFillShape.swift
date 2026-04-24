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

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // 1. Clamp progress to 0...1
        let progressClamped = max(0, min(1, progress))

        // Guard against zero-width rects (layout pass race).
        guard rect.width > 0 else { return path }

        // 2. Baseline fill line (y grows downward in SwiftUI).
        //    progress = 0 → baseY = maxY (bottom, empty)
        //    progress = 1 → baseY = minY (top, full)
        let baseY = rect.maxY - (rect.height * progressClamped)

        // 3. Tilt magnitude — how far the waterline tilts end-to-end.
        //    Linear across x: at x=0 → -tiltMag, at x=width → +tiltMag.
        let tiltMag = tiltX * amplitude * 3

        // 4. Sample the wave across the width. 40+ samples keeps the curve
        //    smooth even on wide cards (iPad landscape).
        let sampleCount: CGFloat = 40
        let step = rect.width / sampleCount
        let twoPi = CGFloat.pi * 2

        // Build ordered list of (x, y) along the top (wavy) surface.
        var surfacePoints: [CGPoint] = []
        surfacePoints.reserveCapacity(Int(sampleCount) + 2)

        for x in stride(from: CGFloat(0), through: rect.width, by: step) {
            let normalizedX = x / rect.width            // 0...1
            let tiltDelta = (normalizedX - 0.5) * 2 * tiltMag
            let waveAngle = phase + normalizedX * frequency * twoPi
            let y = baseY + sin(waveAngle) * amplitude + tiltDelta
            surfacePoints.append(CGPoint(x: rect.minX + x, y: y))
        }

        // Ensure the final sample sits exactly on the right edge (stride may
        // stop one step short due to floating-point rounding).
        if let last = surfacePoints.last, last.x < rect.maxX {
            let normalizedX: CGFloat = 1.0
            let tiltDelta = (normalizedX - 0.5) * 2 * tiltMag
            let waveAngle = phase + normalizedX * frequency * twoPi
            let y = baseY + sin(waveAngle) * amplitude + tiltDelta
            surfacePoints.append(CGPoint(x: rect.maxX, y: y))
        }

        // 5. Build a closed path: wavy top → down right edge → bottom → up left.
        guard let first = surfacePoints.first else { return path }
        path.move(to: first)
        for point in surfacePoints.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

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
