import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// ScrollStateStore — Iter 8 P2 (cross-tab scroll preservation)
//
// Holds the most recent scroll position for each high-traffic list
// keyed by a stable string id. SwiftUI's TabView keeps tab subtree
// state alive while the user switches tabs, but list views that get
// rebuilt (sheets, deep-link pops, etc.) lose their scroll offset.
// We park positions in a single MainActor store injected at the
// MainTabView root so any view in the tree can `save / restore`.
//
// Why not @SceneStorage:
//   • SceneStorage encodes a single `Codable` per key — wrappers
//     around `ScrollPosition` are not currently Codable, and we
//     also need to round-trip identifier values which are heterogeneous
//     (UUIDs / Strings depending on data source).
//   • Cross-tab restoration is a per-runtime concern; we don't need
//     to persist across launches (cold-launch scrolls to top is fine).
//
// API surface — minimal on purpose:
//   • `position(for:)` — read the saved offset for a key. Caller
//     applies it via `.scrollPosition(...)`.
//   • `save(_:for:)` — record an offset before the view disappears.
//   • `clear(_:)` — drop a key (e.g. on logout / tab reset).
//
// Apply pattern (per high-traffic list view):
//
//   @EnvironmentObject private var scrollStore: ScrollStateStore
//   @State private var scrollPosition = ScrollPosition()
//
//   List { ... }
//       .scrollPosition($scrollPosition)
//       .onAppear {
//           if let saved = scrollStore.position(for: "tasks-list") {
//               scrollPosition = saved
//           }
//       }
//       .onDisappear {
//           scrollStore.save(scrollPosition, for: "tasks-list")
//       }
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ScrollStateStore: ObservableObject {
    /// Stable keys reserved for the high-traffic lists this store backs.
    /// Strings are namespaced (`feature.surface`) so future views don't
    /// accidentally collide with each other.
    public enum Key {
        public static let tasks         = "tasks.list"
        public static let approvals     = "approvals.list"
        public static let reportingDaily  = "reporting.daily"
        public static let reportingWeekly = "reporting.weekly"
        public static let announcements = "announcements.list"
        public static let messages      = "messages.list"
        public static let dashboard     = "dashboard.main"
    }

    /// Backing dictionary. Published so SwiftUI re-renders any observer
    /// that depends on the saved state (rare — most consumers read once
    /// in `.onAppear` and don't observe further).
    @Published private var positions: [String: ScrollPosition] = [:]

    public init() {}

    public func position(for key: String) -> ScrollPosition? {
        positions[key]
    }

    public func save(_ pos: ScrollPosition, for key: String) {
        positions[key] = pos
    }

    public func clear(_ key: String) {
        positions.removeValue(forKey: key)
    }

    public func clearAll() {
        positions.removeAll()
    }
}
