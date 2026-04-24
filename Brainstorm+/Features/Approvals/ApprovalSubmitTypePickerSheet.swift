import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Type picker sheet.
//
// Small chooser rendered when the user taps "+" in ApprovalCenterView's
// toolbar. Mirrors Web's approach in `src/app/dashboard/approval/
// page.tsx` where the new-request dialog starts on a type selector
// before swapping to the per-type form. We split this into its own
// sheet so ApprovalCenterView doesn't juggle two presentation states
// (type chooser + per-type form) in the same `.sheet`.
//
// Flow: user taps an option → we dismiss this sheet and call
// `onSelect(kind)` — the parent then presents the matching submit
// sheet. Using a callback rather than pushing the next sheet from
// inside this view keeps presentation ownership at the parent.
// ══════════════════════════════════════════════════════════════════

public enum ApprovalSubmitKind: String, CaseIterable, Identifiable {
    case leave
    case reimbursement
    case procurement
    case fieldWork = "field_work"
    // Batch B.3 — business trip submission. Writes directly to
    // `business_trip_requests` (migration 045); no RPC on the server
    // because Web never shipped this form. See BusinessTripSubmitView
    // header for the trust-boundary rationale.
    case businessTrip = "business_trip"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .leave:         return "请假"
        case .reimbursement: return "报销"
        case .procurement:   return "采购"
        case .fieldWork:     return "外勤"
        case .businessTrip:  return "出差"
        }
    }

    /// SF Symbol for the row icon. Chosen to match the Web iconography
    /// (calendar for leave, receipt for reimbursement, bag for
    /// procurement, map-pin for field-work, airplane for business trip).
    public var systemImage: String {
        switch self {
        case .leave:         return "calendar"
        case .reimbursement: return "doc.text.magnifyingglass"
        case .procurement:   return "bag"
        case .fieldWork:     return "mappin.and.ellipse"
        case .businessTrip:  return "airplane"
        }
    }

    public var subtitle: String {
        switch self {
        case .leave:         return "年假 · 病假 · 调休等"
        case .reimbursement: return "差旅 · 餐饮 · 设备等报销"
        case .procurement:   return "设备 · 软件 · SaaS 采购"
        case .fieldWork:     return "外勤记录，至少提前一天"
        case .businessTrip:  return "跨城市出差行程登记"
        }
    }
}

public struct ApprovalSubmitTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Fires after the sheet dismisses itself. Parent re-presents the
    /// matching per-type submit sheet.
    private let onSelect: (ApprovalSubmitKind) -> Void

    public init(onSelect: @escaping (ApprovalSubmitKind) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            List(ApprovalSubmitKind.allCases) { kind in
                Button {
                    dismiss()
                    onSelect(kind)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: kind.systemImage)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(BsColor.brandAzure)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.displayLabel)
                                .font(.body.weight(.medium))
                                .foregroundStyle(BsColor.ink)
                            Text(kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(BsColor.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .navigationTitle("新建审批")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ApprovalSubmitTypePickerSheet { _ in }
}
