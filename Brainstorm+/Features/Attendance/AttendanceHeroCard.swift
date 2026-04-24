// ═══════════════════════════════════════════════════════════════════════
// AttendanceHeroCard.swift
// BrainStorm+
//
// Signature View A — Dashboard top hero card.
// Reference: docs/plans/2026-04-24-ios-full-redesign-plan.md §2.6 Signature A
//
// Composition:
//   • BsHeroCard (Liquid Glass container w/ top inset highlight)
//   • LiquidFillShape fill layer driven by TimelineView(.animation) sine wave
//     — progress = worked hours / 8h, tilted via BsMotionManager gyroscope
//   • Overlay: status pill, hero number "X 小时 Y 分", CTA, timestamps+location
//
// State color rules:
//   .ready      → inkFaint (empty)
//   .clockedIn  → brandAzure (working)
//   .done <8h   → brandMint (完成)
//   .done ≥8h   → brandCoral (加班 — overtime gets admin coral)
// ═══════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

public struct AttendanceHeroCard: View {

    // MARK: - Inputs

    @ObservedObject var viewModel: AttendanceViewModel
    /// Passed from Dashboard. Placeholder for future layout branching — card
    /// always renders identically regardless of this flag today.
    let isEmbedded: Bool

    public init(viewModel: AttendanceViewModel, isEmbedded: Bool = true) {
        self.viewModel = viewModel
        self.isEmbedded = isEmbedded
    }

    // MARK: - Environment / Motion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = BsMotionManager()
    @State private var lowPowerActive: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    // MARK: - Body

    public var body: some View {
        BsHeroCard(padding: 0) {
            ZStack(alignment: .bottomLeading) {
                // ─── Liquid fill layer ────────────────────────────────────
                // ─── 粘稠发光能量液（Build Driver 风）──────────────────
                // 参数走 viscous（honey/molten metal）：amp 小 / freq 长 / 慢速
                // 4 层栈：
                //   Layer 0: outer halo — stateColor 在液体外扩散 neon glow
                //   Layer 1: body gradient — 亮度推到 0.45–0.85 出能量感
                //   Layer 2: rising bubbles — Canvas 画 7 个气泡持续升起（ clipped to body）
                //   Layer 3: neon surface line — 白 stroke + stateColor 双层 shadow glow
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat(t) * 1.4          // 粘稠慢速（honey-like）
                    let amp: CGFloat = reduceMotion ? 0 : 9
                    let freq: CGFloat = 1.2               // 长波长（粘性流体）
                    let tilt: CGFloat = reduceMotion ? 0 : motion.tiltX

                    ZStack {
                        // Layer 0: 外层发光 halo
                        LiquidFillShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .fill(stateColor.opacity(0.55))
                            .blur(radius: 18)

                        // Layer 1: 主体亮渐变
                        LiquidFillShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        stateColor.opacity(0.85),
                                        stateColor.opacity(0.65),
                                        stateColor.opacity(0.45),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )

                        // Layer 2: 上升气泡（Canvas，clipped to liquid body）
                        if !reduceMotion {
                            Canvas(rendersAsynchronously: true) { gctx, size in
                                let liquidRect = CGRect(origin: .zero, size: size)
                                let liquidPath = LiquidFillShape(
                                    progress: progress, phase: phase, tiltX: tilt,
                                    amplitude: amp, frequency: freq
                                ).path(in: liquidRect)
                                gctx.clip(to: liquidPath)
                                Self.drawBubbles(into: gctx, size: size, time: t, progress: progress)
                            }
                        }

                        // Layer 3: neon 水面高光线 + 双层 shadow glow
                        LiquidSurfaceLineShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .stroke(Color.white.opacity(0.82), lineWidth: 1.4)
                            .shadow(color: stateColor.opacity(0.95), radius: 3)
                            .shadow(color: stateColor.opacity(0.55), radius: 9)
                    }
                }
                // 注入/打卡 瞬间：interpolatingSpring underdamped 有 overshoot
                // 不是 smooth ease —— 是能量冲击的爆发感
                .animation(
                    .interpolatingSpring(mass: 1.3, stiffness: 55, damping: 9),
                    value: progress
                )
                .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.55), value: motion.tiltX)

                // ─── Content overlay ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    statusPill
                    heroNumber
                    Spacer(minLength: 8)
                    ctaRow
                }
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
            .frame(minHeight: 240)
        }
        .onAppear {
            if !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                motion.start()
            }
        }
        .onDisappear { motion.stop() }
        .onChange(of: lowPowerActive) { _, active in
            if active {
                motion.stop()
            } else if !reduceMotion {
                motion.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // Phase 7: Hero 数字 48pt 在 XXXL+ 会炸布局，clamp 到 xxLarge
        // （系统 Large Title 放大范围内封顶，辅助功能用户仍能读出所有文字）
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    /// VoiceOver 一次读出整张卡的核心信息（状态 + 工时 + 提示）
    private var a11yLabel: String {
        let status = statusLabel
        let hrs = Int(progress * 8)
        let mins = Int(progress * 8 * 60) % 60
        return "今日打卡：\(status)，已工作 \(hrs) 小时 \(mins) 分，\(heroSubtitle)"
    }

    // MARK: - Sub-views

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon).font(.system(size: 11, weight: .semibold))
            Text(statusLabel).font(.custom("Inter-SemiBold", size: 11))
        }
        .foregroundStyle(stateColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(stateColor.opacity(0.14), in: Capsule())
    }

    private var heroNumber: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hoursText)
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("小时")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
                Text(minutesText)
                    .font(BsTypography.heroNumber)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("分")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.inkMuted)
                    .baselineOffset(8)
            }
            Text(heroSubtitle)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            BsPrimaryButton(ctaLabel, isLoading: viewModel.isLoading, isDisabled: ctaDisabled) {
                Task { await viewModel.punch() }
            }
            Spacer()
            if let clockIn = viewModel.today?.clockIn {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTime(clockIn) + (viewModel.today?.clockOut.map { " – \(formatTime($0))" } ?? ""))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BsColor.inkMuted)
                        .monospacedDigit()
                    if viewModel.hasLocation,
                       let loc = viewModel.currentLocationName,
                       !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: 11))
                            .foregroundStyle(BsColor.inkFaint)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Derived state

    /// Worked fraction of an 8h day, clamped to [0, 1].
    private var progress: CGFloat {
        switch viewModel.clockState {
        case .ready:
            return 0
        case .clockedIn:
            guard let clockIn = viewModel.today?.clockIn else { return 0 }
            let elapsed = Date().timeIntervalSince(clockIn)
            return CGFloat(max(0, min(1, elapsed / 28_800)))
        case .done:
            guard let clockIn = viewModel.today?.clockIn,
                  let clockOut = viewModel.today?.clockOut else { return 0 }
            let elapsed = clockOut.timeIntervalSince(clockIn)
            return CGFloat(max(0, min(1, elapsed / 28_800)))
        }
    }

    private var stateColor: Color {
        switch viewModel.clockState {
        case .ready:
            return BsColor.inkFaint
        case .clockedIn:
            return BsColor.brandAzure
        case .done:
            return progress >= 1.0 ? BsColor.brandCoral : BsColor.brandMint
        }
    }

    private var statusLabel: String {
        switch viewModel.clockState {
        case .ready:     return "待打卡"
        case .clockedIn: return "已打卡"
        case .done:      return progress >= 1.0 ? "加班中" : "已下班"
        }
    }

    private var statusIcon: String {
        switch viewModel.clockState {
        case .ready:     return "clock"
        case .clockedIn: return "clock.fill"
        case .done:      return "checkmark.circle.fill"
        }
    }

    private var hoursText: String { String(Int(progress * 8)) }

    private var minutesText: String {
        let totalMinutes = Int(progress * 8 * 60)
        return String(totalMinutes % 60)
    }

    private var heroSubtitle: String {
        switch viewModel.clockState {
        case .ready:
            return "点击开始新的一天"
        case .clockedIn:
            return "持续工作中 · 目标 8 小时"
        case .done:
            return progress >= 1.0
                ? "超出目标 \(Int((progress - 1) * 100))%"
                : "今日已结束"
        }
    }

    private var ctaLabel: String {
        switch viewModel.clockState {
        case .ready:     return "上班打卡"
        case .clockedIn: return "下班打卡"
        case .done:      return "已完成"
        }
    }

    private var ctaDisabled: Bool { viewModel.clockState == .done }

    // MARK: - Formatter

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Bubble renderer（上升能量粒子）

    /// 在液体内部画 7 个持续升起的白色气泡粒子（Build Driver 能量感）。
    /// 每个粒子参数由 index seed 确定：上升速度 / x 抖动 / 半径 / cycle 错相。
    /// 用 Canvas imperative 画，外层 TimelineView 驱动 time，成本低于 N 个 SwiftUI View。
    nonisolated fileprivate static func drawBubbles(
        into ctx: GraphicsContext,
        size: CGSize,
        time t: TimeInterval,
        progress: CGFloat
    ) {
        let progressClamped = max(0, min(1, progress))
        let fillTopY = size.height * (1 - progressClamped)
        let bubbleBottom = size.height - 4
        // 液体太浅（< 24pt）就不画气泡，否则挤
        guard bubbleBottom - fillTopY > 24 else { return }

        let bubbleCount = 7
        for i in 0..<bubbleCount {
            let seed = Double(i) * 0.371

            // 每粒气泡周期 2.2 – 4.2 秒（不同速率）
            let cycle = 2.2 + (1.0 + cos(seed * 2.7)) * 1.0
            let bubbleT = fmod(t + seed * 5.0, cycle)
            let rise = bubbleT / cycle   // 0..1 归一化

            // x 位置：7 点均布 + 微幅 x 抖动
            let xBase = Double(size.width) * (0.1 + Double(i) * 0.117)
            let xJitter = sin(rise * 3.8 + seed) * 6.0
            let x = xBase + xJitter

            // y 位置：从底部升到液面
            let totalRise = Double(bubbleBottom) - Double(fillTopY)
            let y = Double(bubbleBottom) - rise * totalRise

            // 半径：1.8 – 3.8pt，随 rise 略微膨胀（向上减压）
            let baseRadius = 1.8 + Double(i % 3) * 0.7
            let radius = baseRadius * (1.0 + rise * 0.25)

            // alpha：起止 fade in/out
            let alphaFade: Double
            if rise < 0.12 { alphaFade = rise / 0.12 }
            else if rise > 0.82 { alphaFade = max(0, (1.0 - rise) / 0.18) }
            else { alphaFade = 1.0 }
            let alpha = 0.55 * alphaFade

            let r = CGFloat(radius)
            let cx = CGFloat(x)
            let cy = CGFloat(y)
            let ellipse = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.fill(ellipse, with: .color(.white.opacity(alpha)))
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        BsColor.pageBackground.ignoresSafeArea()
        VStack {
            AttendanceHeroCard(viewModel: AttendanceViewModel())
                .padding()
            Spacer()
        }
    }
}
