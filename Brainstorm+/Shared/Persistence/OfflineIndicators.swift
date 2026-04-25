import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Offline indicators — Iter 6 review §B.4 surface
//
// Two small SwiftUI primitives that consume `NetworkMonitor.shared`
// without forcing every list view to copy/paste the same logic:
//
//   • OfflineCachedBanner — slim banner that lists show ABOVE their
//     content when the network is down AND we're rendering cached
//     data ("网络断开,显示离线缓存"). The list itself stays
//     populated; only the banner overlays.
//
//   • OfflineToolbarIndicator — gray cloud-slash icon that sits in
//     a toolbar so the user always has a single place to confirm
//     network state. Renders nothing when online.
//
// Both are intentionally tiny so they can be dropped into any
// existing list view without restructuring layout.
// ══════════════════════════════════════════════════════════════════

public struct OfflineCachedBanner: View {
    @ObservedObject private var monitor = NetworkMonitor.shared

    public init() {}

    public var body: some View {
        if !monitor.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .imageScale(.small)
                Text("网络断开,显示离线缓存")
                    .font(.footnote)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(.separator),
                alignment: .bottom
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

public struct OfflineToolbarIndicator: View {
    @ObservedObject private var monitor = NetworkMonitor.shared

    public init() {}

    public var body: some View {
        if !monitor.isOnline {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel("离线")
                .transition(.opacity)
        }
    }
}
