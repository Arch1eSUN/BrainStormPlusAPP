import SwiftUI
import MapKit
import CoreLocation

struct AdminGeofenceEditSheet: View {
    let initial: Geofence
    let onSave: (Geofence) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var address: String
    @State private var radius: Double
    @State private var center: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition
    @State private var latInput: String
    @State private var lngInput: String
    @State private var showCoordinateEditor: Bool = false
    @State private var coordinateError: String?

    init(initial: Geofence, onSave: @escaping (Geofence) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _name = State(initialValue: initial.name)
        _address = State(initialValue: initial.address)
        _radius = State(initialValue: Double(initial.radius))
        _latInput = State(initialValue: initial.lat.map { String(format: "%.6f", $0) } ?? "")
        _lngInput = State(initialValue: initial.lng.map { String(format: "%.6f", $0) } ?? "")
        if let lat = initial.lat, let lng = initial.lng {
            let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            _center = State(initialValue: c)
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: c,
                latitudinalMeters: max(Double(initial.radius) * 4, 400),
                longitudinalMeters: max(Double(initial.radius) * 4, 400)
            )))
        } else {
            // default to Beijing (approximate) if no coordinates
            let fallback = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
            _center = State(initialValue: nil)
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: fallback,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("办公区名称", text: $name)
                    TextField("地标 / 详细地址（可选）", text: $address)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("允许打卡半径")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            Slider(value: $radius, in: 50...2000, step: 10)
                            Text("\(Int(radius)) 米")
                                .font(.footnote.monospacedDigit())
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("半径 (50 ~ 2000 米)")
                }

                Section {
                    MapReader { reader in
                        Map(position: $cameraPosition) {
                            if let c = center {
                                Marker(name.isEmpty ? "中心" : name, coordinate: c)
                                MapCircle(center: c, radius: radius)
                                    .foregroundStyle(BsColor.brandAzure.opacity(0.2))
                                    .stroke(BsColor.brandAzure, lineWidth: 1.5)
                            }
                        }
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .local)
                                .onEnded { event in
                                    if let coord = reader.convert(event.location, from: .local) {
                                        center = coord
                                        latInput = String(format: "%.6f", coord.latitude)
                                        lngInput = String(format: "%.6f", coord.longitude)
                                        coordinateError = nil
                                    }
                                }
                        )
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                        Text("轻点地图任意位置设置中心点")
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                } header: {
                    Text("在地图上选点")
                }

                Section {
                    DisclosureGroup("手动输入经纬度", isExpanded: $showCoordinateEditor) {
                        HStack {
                            Text("纬度").frame(width: 40, alignment: .leading)
                            TextField("例：39.904200", text: $latInput)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        HStack {
                            Text("经度").frame(width: 40, alignment: .leading)
                            TextField("例：116.407400", text: $lngInput)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            applyManualCoordinate()
                        } label: {
                            Label("应用坐标", systemImage: "scope")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)

                        if let err = coordinateError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(BsColor.danger)
                        }
                    }
                }

                if let c = center {
                    Section("当前选择") {
                        HStack {
                            Text("纬度")
                            Spacer()
                            Text(String(format: "%.6f", c.latitude))
                                .font(.footnote.monospaced())
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        HStack {
                            Text("经度")
                            Spacer()
                            Text(String(format: "%.6f", c.longitude))
                                .font(.footnote.monospaced())
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                }
            }
            .navigationTitle(initial.name.isEmpty || initial.name == "新办公区" ? "新建打卡点" : "编辑打卡点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveAndDismiss() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && center != nil
    }

    private func applyManualCoordinate() {
        guard let lat = Double(latInput.trimmingCharacters(in: .whitespaces)),
              let lng = Double(lngInput.trimmingCharacters(in: .whitespaces)) else {
            coordinateError = "请输入有效的数字经纬度"
            return
        }
        guard (-90...90).contains(lat), (-180...180).contains(lng) else {
            coordinateError = "坐标超出合法范围"
            return
        }
        coordinateError = nil
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        center = c
        cameraPosition = .region(MKCoordinateRegion(
            center: c,
            latitudinalMeters: max(radius * 4, 400),
            longitudinalMeters: max(radius * 4, 400)
        ))
    }

    private func saveAndDismiss() {
        guard let c = center else { return }
        var updated = initial
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.address = address.trimmingCharacters(in: .whitespaces)
        updated.radius = Int(radius)
        updated.lat = c.latitude
        updated.lng = c.longitude
        onSave(updated)
        dismiss()
    }
}
