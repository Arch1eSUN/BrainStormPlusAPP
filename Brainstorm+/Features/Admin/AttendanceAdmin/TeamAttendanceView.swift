import SwiftUI

// ══════════════════════════════════════════════════════════════════
// TeamAttendanceView —— 全员考勤（Admin 专属）
//
// Phase 0b：填补 iOS 缺失的 "admin 看团队打卡" 功能。
//
// 内容：
//   • 顶部日期选择（默认今日）+ 部门筛选（Menu）
//   • 快览 chip：出勤 N / 未打卡 N
//   • 员工列表：头像 + 姓名/部门 + 状态 pill + 打卡/下班时间
//   • 搜索（姓名 / 部门）
//   • Pull-to-refresh
//
// 架构：按 plan 2.8 签名，接受 isEmbedded 参数化（为 Phase 3 准备）
// ══════════════════════════════════════════════════════════════════

public struct TeamAttendanceView: View {
    @StateObject private var viewModel = TeamAttendanceViewModel()

    let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        List {
            // Section header —— 日期 + 部门筛选 + 快览
            Section {
                headerControls
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            // 员工列表
            if viewModel.filteredRows.isEmpty && !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        viewModel.searchQuery.isEmpty ? "暂无数据" : "没有匹配的员工",
                        systemImage: viewModel.searchQuery.isEmpty ? "person.2.slash" : "magnifyingglass",
                        description: Text(viewModel.searchQuery.isEmpty ?
                            "当前日期或部门下没有员工打卡记录" :
                            "换个关键词再试")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.filteredRows) { row in
                        memberRow(row)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .searchable(text: $viewModel.searchQuery, prompt: "搜索姓名 / 部门")
        .refreshable {
            Haptic.soft()
            await viewModel.load()
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.selectedDate) { _, _ in
            Task { await viewModel.load() }
        }
        .zyErrorBanner($viewModel.errorMessage)
        .navigationTitle("全员考勤")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header controls

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 日期选择器
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(BsColor.brandAzure)
                DatePicker("日期", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(BsColor.brandAzure)

                Spacer()

                // 部门筛选
                Menu {
                    Button {
                        viewModel.departmentFilter = nil
                    } label: {
                        Label("全部部门", systemImage: viewModel.departmentFilter == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(viewModel.allDepartments, id: \.self) { dept in
                        Button {
                            viewModel.departmentFilter = dept
                        } label: {
                            Label(dept, systemImage: viewModel.departmentFilter == dept ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(viewModel.departmentFilter ?? "全部")
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BsColor.brandAzure)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(BsColor.brandAzure.opacity(0.14)).interactive(), in: Capsule())
                }
            }

            // 快览 chips
            HStack(spacing: 10) {
                summaryChip(label: "已出勤", count: viewModel.presentCount, tint: BsColor.brandMint)
                summaryChip(label: "未打卡", count: viewModel.absentCount, tint: BsColor.brandCoral)
                Spacer()
            }
        }
    }

    private func summaryChip(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BsColor.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }

    // MARK: - Member row

    private func memberRow(_ row: TeamAttendanceViewModel.Row) -> some View {
        HStack(spacing: 12) {
            avatar(for: row.profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.fullName)
                    .font(.custom("Inter-SemiBold", size: 15))
                    .foregroundStyle(BsColor.ink)
                if !row.department.isEmpty {
                    Text(row.department)
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                statusPill(for: row)
                HStack(spacing: 4) {
                    Text(row.clockInText)
                    Text("-")
                        .foregroundStyle(BsColor.inkFaint)
                    Text(row.clockOutText)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func avatar(for profile: Profile) -> some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.12))
            Text(String(profile.fullName?.prefix(1) ?? "?"))
                .font(.custom("Inter-SemiBold", size: 16))
                .foregroundStyle(BsColor.brandAzure)
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private func statusPill(for row: TeamAttendanceViewModel.Row) -> some View {
        let (tint, iconName): (Color, String) = {
            switch row.statusLabel {
            case "已打卡":  return (BsColor.brandMint, "clock.fill")
            case "已下班":  return (BsColor.brandMint, "checkmark.circle.fill")
            case "请假":    return (BsColor.warning, "bed.double.fill")
            case "出差":    return (BsColor.brandAzure, "airplane")
            case "外勤":    return (BsColor.brandCoral, "figure.walk")
            default:       return (BsColor.inkFaint, "clock")
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text(row.statusLabel)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    TeamAttendanceView()
}
