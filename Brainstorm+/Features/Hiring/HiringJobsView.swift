import SwiftUI

public struct HiringJobsView: View {
    @StateObject private var viewModel = HiringJobsViewModel()
    @State private var editTarget: JobEditTarget?

    public init() {}

    public var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.positions.isEmpty {
                ProgressView().padding(.top, 40)
            } else if viewModel.positions.isEmpty {
                ContentUnavailableView(
                    "暂无岗位",
                    systemImage: "briefcase",
                    description: Text("点击右上角「新建岗位」发布第一个招聘岗位。")
                )
            } else {
                List {
                    ForEach(viewModel.positions) { pos in
                        Button {
                            editTarget = .edit(pos)
                        } label: {
                            row(pos)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(pos) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editTarget = .edit(pos)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索岗位/部门")
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editTarget = .new
                } label: {
                    Label("新建岗位", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editTarget) { target in
            HiringJobEditSheet(existing: target.position) {
                Task { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private func row(_ pos: JobPosition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pos.title)
                    .font(.headline)
                Spacer()
                statusBadge(pos.status)
            }
            HStack(spacing: 8) {
                if let dept = pos.department, !dept.isEmpty {
                    Label(dept, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(pos.employmentType.displayLabel, systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sr = pos.salaryRange, !sr.isEmpty {
                    Label(sr, systemImage: "yensign.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let desc = pos.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ status: JobPosition.PositionStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color(for: status).opacity(0.15))
            .foregroundStyle(color(for: status))
            .clipShape(Capsule())
    }

    private func color(for status: JobPosition.PositionStatus) -> Color {
        switch status {
        case .open:    return .green
        case .onHold:  return .orange
        case .filled:  return .blue
        case .closed:  return .secondary
        }
    }
}

private enum JobEditTarget: Identifiable {
    case new
    case edit(JobPosition)

    var id: String {
        switch self {
        case .new:            return "new"
        case .edit(let pos):  return pos.id.uuidString
        }
    }

    var position: JobPosition? {
        switch self {
        case .new:            return nil
        case .edit(let pos):  return pos
        }
    }
}
