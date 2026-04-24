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
    /// 今日排班（v1.3）：决定 overtime 阈值。
    /// - 无值 / flexibleHours == true → 按 8h 算（弹性工时默认）
    /// - 有 expectedStart + expectedEnd → 两者时差作为目标工时（部门固定班次）
    let todayState: DailyWorkState?

    public init(
        viewModel: AttendanceViewModel,
        isEmbedded: Bool = true,
        todayState: DailyWorkState? = nil
    ) {
        self.viewModel = viewModel
        self.isEmbedded = isEmbedded
        self.todayState = todayState
    }

    // MARK: - Environment / Motion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = BsMotionManager()
    @State private var lowPowerActive: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    // MARK: - v1.3 色彩状态机（overtime + 跨日重置）
    //
    // 状态图：
    //   .ready       → 空池（progress=0, 不 render 液体 body）
    //   .clockedIn   → 液体 Azure → Mint 按 progress 线性插值（同色系）
    //   .done (<8h)  → 定格 Mint
    //   8h crossing  → Coral 自下而上覆盖（~1.3s rise），Haptic.warning 一次
    //   overtime     → 液体定格 Coral，不再随 progress 变色
    //   跨日 (attendance.date 变) → hasHitOvertime 重置，重新开始循环

    /// 今天是否已触发 overtime Coral 覆盖（@AppStorage 持久跨 app 生命周期）
    @AppStorage("bs_attendance_overtime_today") private var hasHitOvertime: Bool = false

    /// 最后记录的工作日 ISO date（YYYY-MM-DD）用于跨日检测
    @AppStorage("bs_attendance_last_day") private var lastWorkDay: String = ""

    /// Overtime Coral 自下而上 rise 的 progress（0=完全未覆盖，1=已完全覆盖）
    /// 动画过渡期间从 0 平滑到 1.0，之后 hasHitOvertime 接管常驻。
    @State private var overtimeRiseProgress: CGFloat = 0

    /// 正在播放 overtime 覆盖动画（1.3s 窗口），防重复触发
    @State private var isOvertimeRising: Bool = false

    // MARK: - Body

    public var body: some View {
        BsHeroCard(padding: 0) {
            ZStack(alignment: .bottomLeading) {
                // ─── Liquid fill layer ────────────────────────────────────
                // ─── 粘稠发光能量液（Build Driver 风，去气泡版）─────────
                // 3 层：
                //   Layer 0: outer halo — stateColor 在液体外扩散 neon glow
                //   Layer 1: body gradient — 亮度 0.45–0.85 能量感
                //   Layer 2: neon surface line — 白 stroke + stateColor 双层 shadow glow
                TimelineView(.animation) { ctx in
                    let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate) * 1.4
                    let amp: CGFloat = reduceMotion ? 0 : 9
                    let freq: CGFloat = 1.2
                    let tilt: CGFloat = reduceMotion ? 0 : motion.tiltX

                    ZStack {
                        // Layer 0: 外层发光 halo（stateColor 决定远场身份感）
                        LiquidFillShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .fill(stateColor.opacity(0.55))
                            .blur(radius: 18)

                        // Layer 1: 液体主体
                        // - 非 overtime：stateColor 按 progress 从 Azure 插值到 Mint（同色系自然过渡）
                        // - overtime: liquidBaseColor 变 Coral，常驻
                        // gradient 纵向用单色系（顶端提亮，底端深）只做深浅，不做跨色
                        LiquidFillShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        liquidBaseColor.opacity(0.90),
                                        liquidBaseColor.opacity(0.72),
                                        liquidBaseColor.opacity(0.48),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )

                        // Layer 2 (overtime rise overlay): 仅在 8h 跨线的 1.3s 覆盖动画期间出现
                        // Coral 从 progress=0 升到 progress=1.0 覆盖整个液面（bottom-up）。
                        // 之后 hasHitOvertime 持久为 true，此 overlay 淡出（overtimeRiseProgress 回 0）。
                        if isOvertimeRising {
                            LiquidFillShape(progress: overtimeRiseProgress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            BsColor.brandCoral.opacity(0.92),
                                            BsColor.brandCoral.opacity(0.72),
                                            BsColor.brandCoral.opacity(0.50),
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .transition(.opacity)
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
            // v1.3 · 跨日检测：对齐 attendance.date 字段的 ISO 日期
            checkNewDayReset()
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
        // v1.3 · 8h crossing 侦测 —— Haptic.warning() + Coral bottom-up rise
        .onChange(of: progress) { _, newValue in
            if !hasHitOvertime && !isOvertimeRising
                && newValue >= 1.0
                && viewModel.clockState == .clockedIn {
                triggerOvertimeRise()
            }
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
            Image(systemName: statusIcon).font(.system(.caption2, weight: .semibold))
            Text(statusLabel).font(BsTypography.label)
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
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(BsColor.inkMuted)
                        .monospacedDigit()
                    if viewModel.hasLocation,
                       let loc = viewModel.currentLocationName,
                       !loc.isEmpty {
                        Text(loc)
                            .font(.system(.caption2))
                            .foregroundStyle(BsColor.inkFaint)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Derived state

    /// 今日工时阈值（秒）—— v1.3 状态机的 progress 基准 + overtime 触发线
    /// 规则：
    ///   • 弹性工时 (flexibleHours == true) → 8h 默认
    ///   • 有固定班次 expectedStart + expectedEnd → 两者时差（自动支持跨天）
    ///   • 缺失数据 → 8h fallback
    private var todayWorkTargetSeconds: TimeInterval {
        guard let state = todayState,
              state.flexibleHours != true,
              let startStr = state.expectedStart,
              let endStr = state.expectedEnd,
              let startSec = Self.parseTimeToSeconds(startStr),
              let endSec = Self.parseTimeToSeconds(endStr)
        else {
            return 28_800  // 8h 弹性默认
        }
        // 支持跨夜班（end 比 start 小）
        let diff = endSec >= startSec ? (endSec - startSec) : (endSec + 86_400 - startSec)
        return max(3_600, diff)  // 安全下限 1h
    }

    /// "HH:MM:SS" 或 "HH:MM" → 秒数
    private static func parseTimeToSeconds(_ hms: String) -> TimeInterval? {
        let parts = hms.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let h = parts[0], m = parts[1]
        let s = parts.count >= 3 ? parts[2] : 0
        return h * 3600 + m * 60 + s
    }

    /// 实际工作经过的秒数（不 clamp），用于 hero 数字显示 + overtime 余分钟计算
    private var elapsedSeconds: TimeInterval {
        switch viewModel.clockState {
        case .ready:
            return 0
        case .clockedIn:
            guard let clockIn = viewModel.today?.clockIn else { return 0 }
            return Date().timeIntervalSince(clockIn)
        case .done:
            guard let clockIn = viewModel.today?.clockIn,
                  let clockOut = viewModel.today?.clockOut else { return 0 }
            return clockOut.timeIntervalSince(clockIn)
        }
    }

    /// 工时进度 [0, 1]，基于今日阈值
    private var progress: CGFloat {
        CGFloat(max(0, min(1, elapsedSeconds / todayWorkTargetSeconds)))
    }

    /// v1.3 · 进度驱动液体底色（Azure 打卡 → Mint 完成 的同色系自然过渡）
    /// - .ready         → inkFaint
    /// - .clockedIn     → Azure ↔ Mint 按 progress 线性插值
    /// - .done (<8h)    → 定格 Mint
    ///
    /// 使用 SwiftUI 原生 `Color.mix(with:by:)`（iOS 18+）保持 dynamic color 正确。
    private var stateColor: Color {
        switch viewModel.clockState {
        case .ready:
            return BsColor.inkFaint
        case .clockedIn:
            return BsColor.brandAzure.mix(with: BsColor.brandMint, by: Double(progress))
        case .done:
            return BsColor.brandMint
        }
    }

    /// 液体主 body 实际使用的色：
    /// - overtime 已触发 → 定格 Coral
    /// - 否则 → stateColor (Azure→Mint interpolation)
    private var liquidBaseColor: Color {
        hasHitOvertime ? BsColor.brandCoral : stateColor
    }

    /// 共享 ISO 日期 formatter（避免每次调用都 alloc）
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// HH:mm 时间 formatter（避免重复 alloc）
    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 今天 ISO 日期（对齐 Attendance 模型的 date 字段）
    private static func todayISO() -> String {
        isoDayFormatter.string(from: Date())
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

    /// 已工作小时数（整数部分），基于实际 elapsed 秒数
    private var hoursText: String {
        String(Int(elapsedSeconds / 3600))
    }

    /// 已工作分钟数（小时余数），基于实际 elapsed 秒数
    private var minutesText: String {
        String(Int(elapsedSeconds / 60) % 60)
    }

    /// Hero subtitle 按状态 + 阈值动态生成
    private var heroSubtitle: String {
        let targetHrs = Int(todayWorkTargetSeconds / 3600)
        let overMinutes = max(0, Int((elapsedSeconds - todayWorkTargetSeconds) / 60))

        switch viewModel.clockState {
        case .ready:
            return "点击开始新的一天"
        case .clockedIn:
            if hasHitOvertime {
                return "加班中 · 已超 \(overMinutes) 分钟"
            }
            return "持续工作中 · 目标 \(targetHrs) 小时"
        case .done:
            if hasHitOvertime {
                return "含加班 +\(overMinutes) 分钟"
            }
            return "今日已结束"
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
        Self.hhmmFormatter.string(from: date)
    }

    // MARK: - v1.3 状态机 transition methods

    /// 8h crossing 瞬间：Coral 自下而上覆盖 rise 动画（1.3s）+ Haptic.warning
    private func triggerOvertimeRise() {
        Haptic.warning()
        isOvertimeRising = true
        overtimeRiseProgress = 0
        // Coral 自下而上 rise：0 → 1.0 over 1.3s
        withAnimation(.smooth(duration: 1.3)) {
            overtimeRiseProgress = 1.0
        }
        // 动画完成后 flip 持久 overtime state，overlay 淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.smooth(duration: 0.25)) {
                hasHitOvertime = true
                isOvertimeRising = false
                overtimeRiseProgress = 0
            }
        }
    }

    /// 跨日检测：如果今天 ISO date 与 lastWorkDay 不同，reset overtime flag
    /// 液体自然 drain（progress 随 viewModel.loadToday() 重置回 0 通过
    /// interpolatingSpring 下降+末端回弹，视觉上就是"排空"动画）。
    private func checkNewDayReset() {
        let today = Self.todayISO()
        if !lastWorkDay.isEmpty && lastWorkDay != today {
            withAnimation(.smooth(duration: 0.3)) {
                hasHitOvertime = false
                isOvertimeRising = false
                overtimeRiseProgress = 0
            }
        }
        lastWorkDay = today
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
