import Foundation
import Network
import Combine

// ══════════════════════════════════════════════════════════════════
// NetworkMonitor — Iter 6 review §B.4 reachability
//
// Wraps NWPathMonitor in an `ObservableObject` so SwiftUI views can
// reactively render an offline indicator and so VMs can react when
// the network comes back. On the offline → online transition we kick
// the WriteActionQueue so any queued mutations replay automatically.
//
// Singleton because there is only one network state per process and
// we want any view in the tree to share the same publisher without
// stacking duplicate path-monitor instances.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class NetworkMonitor: ObservableObject {

    public static let shared = NetworkMonitor()

    /// Truthy when the OS reports the path as `.satisfied`. Defaults
    /// to `true` so the very first render before NWPathMonitor's first
    /// callback doesn't flash an offline banner.
    @Published public private(set) var isOnline: Bool = true

    /// Pretty interface label for diagnostics — populated from the
    /// most-recent NWPath.availableInterfaces.first.type. Not used by
    /// the UI today but handy for debugging "why is my push not coming
    /// through" reports.
    @Published public private(set) var interfaceLabel: String = "wifi"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.brainstorm.network-monitor")
    private var didStart = false

    private init() {}

    /// Begin observing path changes. Idempotent — second call is a
    /// no-op. Caller should invoke this from the App `init` or first
    /// render so the first path callback can flip `isOnline`.
    public func start() {
        guard !didStart else { return }
        didStart = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            let label: String
            if let iface = path.availableInterfaces.first {
                switch iface.type {
                case .wifi:        label = "wifi"
                case .cellular:    label = "cellular"
                case .wiredEthernet: label = "ethernet"
                case .loopback:    label = "loopback"
                case .other:       label = "other"
                @unknown default:  label = "unknown"
                }
            } else {
                label = "none"
            }

            Task { @MainActor in
                let wasOffline = !self.isOnline
                self.isOnline = online
                self.interfaceLabel = label

                if wasOffline && online {
                    // Offline → online transition: drain queued writes.
                    // Detached so the path callback isn't blocked while
                    // the queue replays (each item hits the network).
                    Task.detached(priority: .userInitiated) {
                        await WriteActionQueue.shared.processQueue()
                    }
                }
            }
        }

        monitor.start(queue: queue)
    }

    public func stop() {
        guard didStart else { return }
        didStart = false
        monitor.cancel()
    }
}
