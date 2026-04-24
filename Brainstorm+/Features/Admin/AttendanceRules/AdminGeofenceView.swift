import SwiftUI
import MapKit

public struct AdminGeofenceView: View {
    @StateObject private var vm = AdminGeofenceViewModel()
    @State private var editingFence: Geofence?
    @State private var showingAdd: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(BsColor.brandAzure)
                    Text("您可以配置多个打卡中心点。员工在任意一个允许的半径内均可打卡成功。若未配置任何围栏，则完全不限制打卡位置。")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }

            if vm.fences.isEmpty {
                Section {
                    Text("暂无指定的考勤围栏，目前允许异地打卡")
                        .font(.subheadline)
                        .foregroundStyle(BsColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(Array(vm.fences.enumerated()), id: \.element.id) { index, fence in
                    Section {
                        fenceRow(index: index, fence: fence)
                    }
                }
            }

            if let info = vm.infoMessage {
                Section {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(BsColor.success)
                }
            }
        }
        .navigationTitle("地理围栏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Spacer()
                    Button {
                        Task { _ = await vm.save() }
                    } label: {
                        if vm.isSaving {
                            ProgressView()
                        } else {
                            Label("保存多点规则", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(vm.isSaving || vm.isLoading)
                }
            }
        }
        .sheet(item: $editingFence) { fence in
            AdminGeofenceEditSheet(initial: fence) { updated in
                vm.update(updated)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AdminGeofenceEditSheet(initial: Geofence()) { new in
                vm.update(new)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    @ViewBuilder
    private func fenceRow(index: Int, fence: Geofence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("打卡点 #\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
                Button(role: .destructive) {
                    vm.remove(id: fence.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text(fence.name.isEmpty ? "未命名" : fence.name)
                .font(.headline)

            if !fence.address.isEmpty {
                Label(fence.address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("半径").font(.caption2).foregroundStyle(BsColor.inkFaint)
                    Text("\(fence.radius) 米").font(.footnote.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("经度").font(.caption2).foregroundStyle(BsColor.inkFaint)
                    Text(fence.lng.map { String(format: "%.6f", $0) } ?? "未设置")
                        .font(.footnote.monospaced())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("纬度").font(.caption2).foregroundStyle(BsColor.inkFaint)
                    Text(fence.lat.map { String(format: "%.6f", $0) } ?? "未设置")
                        .font(.footnote.monospaced())
                }
                Spacer()
            }

            if let lat = fence.lat, let lng = fence.lng {
                let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: Double(fence.radius) * 4,
                    longitudinalMeters: Double(fence.radius) * 4
                ))) {
                    Marker(fence.name.isEmpty ? "中心" : fence.name, coordinate: center)
                    MapCircle(center: center, radius: CLLocationDistance(fence.radius))
                        .foregroundStyle(BsColor.brandAzure.opacity(0.2))
                        .stroke(BsColor.brandAzure, lineWidth: 1.5)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            } else {
                HStack {
                    Image(systemName: "mappin.slash")
                        .foregroundStyle(BsColor.inkFaint)
                    Text("尚未设置坐标")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BsColor.inkMuted.opacity(0.08))
                )
            }

            Button {
                editingFence = fence
            } label: {
                Label("编辑打卡点", systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BsColor.brandAzure.opacity(0.1))
                    )
                    .foregroundStyle(BsColor.brandAzure)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
