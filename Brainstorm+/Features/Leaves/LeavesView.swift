import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.2 — Leaves balance + history center
//
// 1:1 port of Web `src/app/dashboard/leaves/page.tsx`.
//
// Layout (top-down, matches Web page.tsx:239-330):
//   1. Header + a "申请请假" gradient button that presents the
//      existing `LeaveSubmitView` modal (brief §Skip — leave
//      submission is already handled by the approvals feature).
//   2. Balance cards — one per leave type. Web shows only `comp_time`
//      in a 3-col grid on desktop; iOS surfaces all 4 (annual / sick /
//      personal / comp_time) per the brief's "Balance cards (one per
//      leave type)" requirement. The extra types are information the
//      user can see on Web via the quota row anyway — the Web card
//      shortlist is a desktop-density choice, not a schema one.
//   3. History list grouped by calendar year (brief §2.3).
//
// Manager/admin view is intentionally skipped this pass (brief
// §Skip — "Manager/admin bulk leave view").
// ══════════════════════════════════════════════════════════════════

public struct LeavesView: View {
    @StateObject private var viewModel: LeavesViewModel
    @State private var isSubmitPresented: Bool = false
    private let client: SupabaseClient

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(client: SupabaseClient = supabase, isEmbedded: Bool = false) {
        self.client = client
        self.isEmbedded = isEmbedded
        _viewModel = StateObject(wrappedValue: LeavesViewModel(client: client))
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg + 4) {
                headerSection

                balanceSection

                historySection
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.lg)
        }
        .background(BsColor.surfaceSecondary.ignoresSafeArea())
        .navigationTitle("请假与调休")
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await viewModel.loadAll()
        }
        .task {
            await viewModel.loadAll()
        }
        .sheet(isPresented: $isSubmitPresented, onDismiss: {
            // After a submit, reload so the new request shows up in
            // history immediately (Web does an optimistic redirect
            // back; we do a plain refetch on dismiss).
            Task { await viewModel.loadAll() }
        }) {
            LeaveSubmitView(client: client) { _ in
                isSubmitPresented = false
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .center, spacing: BsSpacing.md) {
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                Text("假期与调休额度")
                    .font(BsTypography.brandWordmark)
                    .foregroundStyle(BsColor.ink)
                Text("查看您的假期余额及休假记录")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted.opacity(0.7))
            }

            Spacer()

            Button {
                isSubmitPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.caption.weight(.bold))
                    Text("申请请假")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, BsSpacing.md + 2)
                .padding(.vertical, BsSpacing.sm + 2)
                .background(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .foregroundStyle(Color.white)
                .shadow(color: BsColor.brandAzure.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Balance

    @ViewBuilder
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            sectionHeader(icon: "clock.badge.checkmark", title: "本月余额")

            if viewModel.isLoading && viewModel.balances.isEmpty {
                balanceSkeletonGrid
            } else if viewModel.balances.isEmpty {
                EmptyBalanceCard()
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: BsSpacing.md),
                        GridItem(.flexible(), spacing: BsSpacing.md),
                    ],
                    spacing: BsSpacing.md
                ) {
                    ForEach(viewModel.balances) { balance in
                        BalanceCardView(balance: balance)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var balanceSkeletonGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: BsSpacing.md),
                GridItem(.flexible(), spacing: BsSpacing.md),
            ],
            spacing: BsSpacing.md
        ) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .fill(BsColor.surfacePrimary)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                            .stroke(BsColor.borderSubtle, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            sectionHeader(icon: "calendar.circle", title: "最近流转记录")

            if viewModel.isLoading && viewModel.history.isEmpty {
                // 3 skeleton rows — matches page.tsx:284-286
                VStack(spacing: BsSpacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                            .fill(BsColor.surfacePrimary)
                            .frame(height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                                    .stroke(BsColor.borderSubtle, lineWidth: 1)
                            )
                    }
                }
            } else if viewModel.history.isEmpty {
                ContentUnavailableView(
                    "无记录",
                    systemImage: "clock",
                    description: Text("您近期还没有关于请假审批的记录")
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                        .fill(BsColor.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 1)
                )
            } else {
                historyList
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        // Group by year, descending. Brief §2.3 asks for a yearly group.
        let grouped = Dictionary(grouping: viewModel.history) { $0.year }
        let years = grouped.keys.sorted(by: >)

        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            ForEach(years, id: \.self) { year in
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    Text("\(String(year)) 年")
                        .font(BsTypography.outfit(14, weight: "Bold"))
                        .foregroundStyle(BsColor.inkMuted)
                        .padding(.horizontal, BsSpacing.xs)

                    VStack(spacing: BsSpacing.sm) {
                        ForEach(grouped[year] ?? []) { entry in
                            HistoryRowView(entry: entry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared primitives

    @ViewBuilder
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BsColor.brandAzure)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(BsColor.ink)
                .textCase(.uppercase)
                .tracking(1.0)
            Spacer()
        }
        .padding(.horizontal, BsSpacing.xs)
    }
}

// MARK: - Balance card

private struct BalanceCardView: View {
    let balance: LeaveBalance

    private var accentColor: Color {
        // Web uses emerald / blue / orange / purple per card. iOS
        // mirrors that tint palette based on leave type.
        switch balance.leaveType {
        case "annual":    return BsColor.brandAzure             // blue
        case "sick":      return BsColor.warning                // orange
        case "personal":  return Color(hex: "#8b5cf6")          // purple — 保留原值，设计系统无紫
        case "comp_time": return BsColor.success                // emerald
        default:          return BsColor.brandAzure
        }
    }

    private var icon: String {
        switch balance.leaveType {
        case "annual":    return "sun.max.fill"
        case "sick":      return "cross.case.fill"
        case "personal":  return "person.fill"
        case "comp_time": return "cup.and.saucer.fill"
        default:          return "calendar"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
            HStack(alignment: .top, spacing: BsSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentColor)
                }
                Text(balance.displayLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BsColor.ink)

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatDays(balance.remainingDays))
                        .font(BsTypography.brandWordmark)
                        .foregroundStyle(BsColor.ink)
                    Text("剩余")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BsColor.inkMuted.opacity(0.6))
                        .tracking(1.2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("已用 \(formatDays(balance.usedDays))")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted.opacity(0.7))
                    Spacer()
                    Text("总 \(formatDays(balance.totalDays))")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted.opacity(0.7))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BsColor.inkMuted.opacity(0.08))
                        Capsule()
                            .fill(accentColor)
                            .frame(width: proxy.size.width * balance.consumedFraction)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(BsSpacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 1)
        )
    }

    private func formatDays(_ d: Double) -> String {
        // "14" not "14.0", "3.5" stays as "3.5" — matches Web's
        // implicit JS number printing.
        if d == d.rounded() {
            return String(Int(d))
        } else {
            return String(format: "%g", d)
        }
    }
}

private struct EmptyBalanceCard: View {
    var body: some View {
        Text("暂无额度数据")
            .font(.caption)
            .foregroundStyle(BsColor.inkMuted.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .fill(BsColor.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 1)
            )
    }
}

// MARK: - History row

private struct HistoryRowView: View {
    let entry: LeaveHistoryEntry

    private static let createdAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: BsSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entry.leaveTypeLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, BsSpacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(BsColor.inkMuted.opacity(0.08))
                        )
                        .foregroundStyle(BsColor.inkMuted)

                    Text(entry.startDate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                    Text("至")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted.opacity(0.5))
                    Text(entry.endDate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                }

                Text("共计耗用额度：\(formatDays(entry.days)) 天")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                statusChip
                Text(Self.createdAtFormatter.string(from: entry.createdAt))
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted.opacity(0.5))
            }
        }
        .padding(BsSpacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusChip: some View {
        let (fg, bg) = statusColors
        Text(entry.statusLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, BsSpacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }

    private var statusColors: (Color, Color) {
        switch entry.status {
        case "approved":
            return (BsColor.success, BsColor.success.opacity(0.12))
        case "pending":
            return (BsColor.warning, BsColor.warning.opacity(0.12))
        case "rejected":
            return (BsColor.danger, BsColor.danger.opacity(0.12))
        default:
            return (BsColor.inkMuted.opacity(0.8), BsColor.inkMuted.opacity(0.08))
        }
    }

    private func formatDays(_ d: Double) -> String {
        if d == d.rounded() {
            return String(Int(d))
        } else {
            return String(format: "%g", d)
        }
    }
}

#Preview {
    NavigationStack {
        LeavesView()
    }
}
