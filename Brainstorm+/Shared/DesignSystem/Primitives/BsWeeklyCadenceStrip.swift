import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - BsWeeklyCadenceStrip
// ═══════════════════════════════════════════════════════════════════════════
//
// A horizontal 7-dot strip that shows this week's attendance cadence (Mon–Sun).
// Sits below the Attendance hero on Dashboard. Intentionally NOT wrapped in a
// card — it's a bare strip (40pt tall) on the page background.
//
// Visual model per docs/plans/2026-04-24-ios-full-redesign-plan.md §2.6
// Signature C:
//   • Completed past day ........ filled BsColor.brandAzure dot
//   • Today .................... filled dot + scale 1.3 + glow + pulse
//   • Future / uncompleted past  stroked ring (brandAzure @ 25%)
//
// Long-pressing a column (0.4s) fires `onDayLongPress(day)` with a light
// haptic, so the Dashboard can surface a quick peek / detail for that day.
//
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - Data Model

public struct WeekDayCadence: Identifiable, Hashable, Sendable {
    public let id: String        // e.g. "Mon" or ISO "2026-04-20"
    public let shortLabel: String // 1 char Chinese weekday: 一/二/三/四/五/六/日
    public let isCompleted: Bool // 该日已打卡完成
    public let isToday: Bool
    public let isInFuture: Bool  // 本周未到的日

    public init(
        id: String,
        shortLabel: String,
        isCompleted: Bool,
        isToday: Bool,
        isInFuture: Bool
    ) {
        self.id = id
        self.shortLabel = shortLabel
        self.isCompleted = isCompleted
        self.isToday = isToday
        self.isInFuture = isInFuture
    }
}

// MARK: - View

public struct BsWeeklyCadenceStrip: View {
    let days: [WeekDayCadence]
    let onDayLongPress: ((WeekDayCadence) -> Void)?

    public init(
        days: [WeekDayCadence],
        onDayLongPress: ((WeekDayCadence) -> Void)? = nil
    ) {
        self.days = days
        self.onDayLongPress = onDayLongPress
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text(day.shortLabel)
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundStyle(BsColor.inkMuted)
                    dotView(for: day)
                        .frame(width: 14, height: 14)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        Haptic.light()
                        onDayLongPress?(day)
                    }
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "周\(day.shortLabel)"
                    + (day.isCompleted ? " 已完成" : " 未完成")
                    + (day.isToday ? " 今日" : "")
                )
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Dot

    @ViewBuilder
    private func dotView(for day: WeekDayCadence) -> some View {
        // v1.2 · 3 色语义分布
        //   • 过去日已完成 → Mint filled（完成 = 绿灯）
        //   • 今日 → Coral filled + 1.5x scale + glow + pulse（当前注意焦点）
        //   • 未来日 / 过去日未完成 → Ink faint ring（中性）
        if day.isToday {
            Circle()
                .fill(BsColor.brandCoral)
                .frame(width: 12, height: 12)
                .scaleEffect(1.5)
                // Batch 7: migrate 2-layer glow shadow → BsShadow.glow(color:) helper
                // 近光（radius 5, opacity 0.7）+ 远光（radius 10, opacity 0.35）双层
                // 组合营造今日 dot 的 pulse halo。
                .bsShadow(BsShadow.glow(BsColor.brandCoral, opacity: 0.7, radius: 5))
                .bsShadow(BsShadow.glow(BsColor.brandCoral, opacity: 0.35, radius: 10))
                .modifier(TodayPulse(isToday: true))
        } else if day.isCompleted {
            Circle()
                .fill(BsColor.brandMint)
                .frame(width: 10, height: 10)
                // Batch 7: migrate raw mint glow → BsShadow.glow helper
                .bsShadow(BsShadow.glow(BsColor.brandMint, opacity: 0.35, radius: 2))
        } else {
            Circle()
                .stroke(BsColor.inkFaint.opacity(0.35), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }
}

// MARK: - Today Pulse Modifier

private struct TodayPulse: ViewModifier {
    let isToday: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    func body(content: Content) -> some View {
        if isToday && !reduceMotion {
            content
                .opacity(pulse ? 1.0 : 0.6)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BsWeeklyCadenceStrip(
            days: [
                .init(id: "mon", shortLabel: "一", isCompleted: true,  isToday: false, isInFuture: false),
                .init(id: "tue", shortLabel: "二", isCompleted: true,  isToday: false, isInFuture: false),
                .init(id: "wed", shortLabel: "三", isCompleted: true,  isToday: false, isInFuture: false),
                .init(id: "thu", shortLabel: "四", isCompleted: false, isToday: true,  isInFuture: false),
                .init(id: "fri", shortLabel: "五", isCompleted: false, isToday: false, isInFuture: true),
                .init(id: "sat", shortLabel: "六", isCompleted: false, isToday: false, isInFuture: true),
                .init(id: "sun", shortLabel: "日", isCompleted: false, isToday: false, isInFuture: true),
            ]
        ) { day in
            print("long-pressed \(day.id)")
        }
        .padding()
    }
    .frame(maxHeight: .infinity)
    .background(BsColor.pageBackground)
}
