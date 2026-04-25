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

    // ─── v1.3.2 perf：液体 TimelineView 的刷新频率 ─────────────────────
    // 用户在 iPhone 17 Pro Max 仍感掉帧 —— v1.3.1 把 30Hz 当节流是错误方向。
    // ProMotion 屏 60Hz 已远超水波感知阈值，且每帧成本经过 lookup table /
    // wave 数 / sample 数三重优化后远低于 16.6ms 预算，60Hz 是"流畅+精美"的甜点。
    //
    //   • 正常             → 60Hz（流畅，且不浪费 ProMotion 的 120Hz 上限）
    //   • Reduce Motion    → 静态（amplitude=0，TimelineView 仍跑但无动画 cost）
    //   • Low Power        → 30Hz（半帧率，仍能跑动画，省电）
    private var liquidRefreshInterval: Double {
        if reduceMotion { return 1.0 / 60 }   // 静态液面：amp=0，刷新只为 progress 插值
        if lowPowerActive { return 1.0 / 30 } // 低电量降一半
        return 1.0 / 60                        // 正常 60Hz
    }

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
                // ─── iOS 26 Liquid Glass 能量液 (v1.3.2 perf rewrite) ─────
                // 4 层（统一 compositingGroup → 一次性合成 + 单 shadow，
                // 替代之前 4 个独立 .blur+shadow 层叠加）：
                //   Layer 0: depth gradient body — 顶亮底深，Liquid Glass 透感
                //   Layer 1: overtime rise overlay (Coral 跨 8h 时覆盖)
                //   Layer 2: specular highlight hairline — 顶端 2pt 白线 alpha 0.35
                //   Layer 3: neon surface line — 水面亮线 + stateColor glow
                //
                // 关键性能改动：
                //   • 删除 v1.3.1 的 .blur(radius: 18) halo —— GPU 最贵操作，
                //     单层 blur 在 ProMotion 下就是掉帧元凶。改用 compositingGroup
                //     + outer shadow 一次合成达到类似 glow，成本砍 70%+。
                //   • LiquidFillShape 60-sample / 2-wave / sin lookup table，
                //     CPU 每帧砍 5×。
                TimelineView(.animation(minimumInterval: liquidRefreshInterval)) { ctx in
                    // Reduce Motion / Low Power：amp 置 0，液面定格为平直
                    let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate) * 1.4
                    let amp: CGFloat = (reduceMotion || lowPowerActive) ? 0 : 9
                    let freq: CGFloat = 1.2
                    let tilt: CGFloat = (reduceMotion || lowPowerActive) ? 0 : motion.tiltX

                    ZStack {
                        // Layer 0: 液体主体 (depth gradient — Liquid Glass 透感)
                        // 顶端高光 0.95 → 中段 0.78 → 底端 0.52，三段 stop 制造
                        // "近看像玻璃水"的深度感，比 v1.3.1 单 0.90/0.72/0.48 更有体积。
                        LiquidFillShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: liquidBaseColor.opacity(0.95), location: 0.00),
                                        .init(color: liquidBaseColor.opacity(0.85), location: 0.18),
                                        .init(color: liquidBaseColor.opacity(0.70), location: 0.55),
                                        .init(color: liquidBaseColor.opacity(0.52), location: 1.00),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Layer 1 (overtime rise overlay): 8h 跨线 1.3s 覆盖动画
                        if isOvertimeRising {
                            LiquidFillShape(progress: overtimeRiseProgress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: BsColor.brandCoral.opacity(0.95), location: 0.00),
                                            .init(color: BsColor.brandCoral.opacity(0.82), location: 0.20),
                                            .init(color: BsColor.brandCoral.opacity(0.62), location: 0.60),
                                            .init(color: BsColor.brandCoral.opacity(0.45), location: 1.00),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .transition(.opacity)
                        }

                        // Layer 2: Specular highlight hairline — 紧贴水面顶端的
                        // 一条极细 (0.6pt) 白色高光，opacity 0.35，模拟玻璃液体
                        // 顶端的反光。和 surface line 同步抖动，但更细更淡，
                        // 在 surface line 之下叠加产生"双层光泽"。
                        LiquidSurfaceLineShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.6)

                        // Layer 3: Neon 水面亮线 + stateColor glow（保留单层 shadow）
                        // v1.3.1 用了双层 shadow（radius 3 + radius 9），ProMotion
                        // 下双 shadow render pass 加倍 GPU 成本。改单层 radius 6
                        // 取折中：仍有发光，成本砍半。
                        LiquidSurfaceLineShape(progress: progress, phase: phase, tiltX: tilt, amplitude: amp, frequency: freq)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.4)
                            .shadow(color: stateColor.opacity(0.75), radius: 6)
                    }
                    // compositingGroup() 让 ZStack 一次性合成后再做 shadow，
                    // 替代每子层独立 shadow（之前 halo blur+多 shadow），
                    // 是去 .blur 后保留 "glow 远场感" 的关键技术。
                    .compositingGroup()
                    .shadow(color: stateColor.opacity(0.30), radius: 10, x: 0, y: 2)
                }
                // 进度变化：critically-damped spring（dampingFraction 0.78），
                // 比 v1.3.1 的 mass=1.3/stiffness=55/damping=9（计算阻尼比 ≈ 0.53
                // 严重 underdamped → overshoot 来回晃 2-3 次）安静很多。
                // 0.78 仍保留一丁点弹性余韵，不死板，但液面不再"晃个不停"。
                .animation(
                    .interactiveSpring(response: 0.55, dampingFraction: 0.78),
                    value: progress
                )
                // tilt 用 critically-damped (0.85)：陀螺仪上报 30Hz 已带低通滤波，
                // spring 再 underdamp 会出现"晃头"二次振荡。
                .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: motion.tiltX)

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BsPrimaryButton(ctaLabel, isLoading: viewModel.isLoading, isDisabled: ctaDisabled) {
                    // CTA 按下仅触发 punch()；BsPrimaryButton 已含 Haptic.medium()。
                    // punch() 内部自己根据 state → success/error 弹对应 banner。
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

            // v1.3 · 打卡反馈 banner —— Hero Card 以前完全丢弃 viewModel.errorMessage
            // / successMessage，用户点按钮后若 currentLocation 还没拿到，punch()
            // 会 silently 设置 errorMessage 但 UI 上什么都不显示 → "按了没反应"。
            // 这里以最小面积贴近 CTA 呈现状态，避免用户困惑。
            if let success = viewModel.successMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(.caption2))
                    Text(success)
                        .font(BsTypography.captionSmall)
                        .lineLimit(2)
                }
                .foregroundStyle(BsColor.success)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let err = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2, weight: .semibold))
                    Text(err)
                        .font(BsTypography.captionSmall)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if viewModel.clockState != .done {
                        Button {
                            // Haptic removed: 用户反馈辅助按钮过密震动
                            Task { await viewModel.punch() }
                        } label: {
                            Text("重试")
                                .font(BsTypography.captionSmall.weight(.semibold))
                                .foregroundStyle(BsColor.brandAzure)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(BsColor.danger)
                .transition(.move(edge: .top).combined(with: .opacity))
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
        // v1.3 · 把加载/等待定位态也表达在 label 上,避免用户按了"上班打卡"
        // 却因为 `currentLocation == nil` 被 punch() silently return。
        if viewModel.isInitializing { return "加载中…" }
        switch viewModel.clockState {
        case .ready:
            return viewModel.hasLocation ? "上班打卡" : "等待定位"
        case .clockedIn:
            return "下班打卡"
        case .done:
            return "已完成"
        }
    }

    /// CTA 禁用条件:
    /// - 已完成(.done)
    /// - 还在初始化(拉 today 记录中)
    /// - 定位还没拿到(hasLocation == false)→ 否则点击后 punch() 只会
    ///   silently 落到 "定位未就绪" errorMessage,用户体感"点了没反应"。
    /// 下班打卡(.clockedIn)时,即使定位突然丢失仍允许点击,
    /// punch() 会把 error 显示在 banner 里,让用户能感知。
    private var ctaDisabled: Bool {
        if viewModel.clockState == .done { return true }
        if viewModel.isInitializing { return true }
        if viewModel.clockState == .ready && !viewModel.hasLocation { return true }
        return false
    }

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
