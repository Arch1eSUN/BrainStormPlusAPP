import Foundation
import Combine

/// Iter 8 polish — viewport-based read-receipt observer.
///
/// The Iter 7 implementation fired `chat_mark_read` from each MessageBubble's
/// `.onAppear` after a flat 500ms `Task.sleep`. That is over-eager:
///   • Rapidly scrolling through 30 unread messages fires 30 RPCs even
///     though the user obviously didn't *read* messages they only flashed
///     past.
///   • Out-of-viewport messages that briefly enter the LazyVStack pre-render
///     window also got marked as read, leading to false reads near the
///     scroll velocity peak.
///
/// New design:
///   • Each bubble registers itself with `ChatVisibilityTracker` on `.onAppear`
///     — we record `(messageId, firstSeenAt = now)`.
///   • A 1.5s dwell timer (per messageId) fires `markMessageRead` only if
///     the registration is still active by then. Scrolling out before the
///     dwell threshold drops the entry.
///   • Already-read messages (own + ours-already-in-readBy) skip
///     registration entirely so we don't burn CPU on the timer ticks.
///
/// Threshold rationale: 1.5s matches Slack iOS / iMessage delivery-receipt
/// dwell windows. Less than 1s reintroduces false reads on momentum scrolls;
/// more than 2s feels laggy in active conversations.
@MainActor
public final class ChatVisibilityTracker: ObservableObject {
    /// messageId → firstSeenAt. Presence in this map = currently visible.
    private var visible: [UUID: Date] = [:]
    /// messageId → in-flight dwell task. Cancelled when bubble scrolls out
    /// before the dwell threshold elapses.
    private var pending: [UUID: Task<Void, Never>] = [:]
    /// messageIds we've already fired markRead for in this room session.
    /// Cleared on teardown via `reset()`.
    private var fired: Set<UUID> = []

    /// Dwell threshold before firing chat_mark_read.
    public let dwellThreshold: TimeInterval

    /// Callback into ChatRoomViewModel.markMessageRead. Wired from the View
    /// at construction time so the tracker stays UI-agnostic.
    private let onMarkRead: (UUID) async -> Void

    public init(dwellThreshold: TimeInterval = 1.5,
                onMarkRead: @escaping (UUID) async -> Void) {
        self.dwellThreshold = dwellThreshold
        self.onMarkRead = onMarkRead
    }

    /// Called from MessageBubble.onAppear. Idempotent — repeated registrations
    /// for the same id keep the original firstSeenAt timestamp.
    public func register(_ messageId: UUID) {
        guard !fired.contains(messageId) else { return }
        guard visible[messageId] == nil else { return }
        visible[messageId] = Date()

        // Schedule dwell-threshold check. If the bubble unregisters before
        // then, the cancellation guard at the top short-circuits.
        let task = Task { [weak self, messageId] in
            try? await Task.sleep(nanoseconds: UInt64((self?.dwellThreshold ?? 1.5) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.fireIfStillVisible(messageId)
        }
        pending[messageId] = task
    }

    /// Called from MessageBubble.onDisappear. Drops the registration so the
    /// dwell timer (if any) becomes a no-op.
    public func unregister(_ messageId: UUID) {
        visible.removeValue(forKey: messageId)
        pending[messageId]?.cancel()
        pending.removeValue(forKey: messageId)
    }

    /// Reset on room teardown so the tracker can be reused if the same view
    /// is re-entered without recreation.
    public func reset() {
        for (_, task) in pending { task.cancel() }
        pending.removeAll()
        visible.removeAll()
        fired.removeAll()
    }

    private func fireIfStillVisible(_ messageId: UUID) async {
        guard visible[messageId] != nil else { return }
        guard !fired.contains(messageId) else { return }
        fired.insert(messageId)
        pending.removeValue(forKey: messageId)
        await onMarkRead(messageId)
    }
}
