import UIKit

/// Thread-safe haptic feedback manager for triggering haptic patterns.
/// Use `HapticManager.shared.trigger(_ feedback:)` to trigger haptics.
@MainActor
final class HapticManager {
  /// Shared singleton instance
  static let shared = HapticManager()
  
  private let generator = UIImpactFeedbackGenerator()
  private let notificationGenerator = UINotificationFeedbackGenerator()
  private let selectionGenerator = UISelectionFeedbackGenerator()
  
  private init() {}
  
  // MARK: - Haptic Types
  enum HapticFeedback {
    case light
    case soft
    case medium
    case rigid
    case error
    case success
  }
  
  // MARK: - Public Methods
  /// Triggers a haptic feedback pattern.
  /// - Parameter feedback: The type of haptic feedback to trigger.
  func trigger(_ feedback: HapticFeedback) {
    switch feedback {
    case .light:
      triggerImpact(.light)
    case .soft:
      triggerImpact(.light)
    case .medium:
      triggerImpact(.medium)
    case .rigid:
      triggerImpact(.heavy)
    case .error:
      triggerNotification(.error)
    case .success:
      triggerNotification(.success)
    }
  }
  
  // MARK: - Private Methods
  private func triggerImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let impact = UIImpactFeedbackGenerator(style: style)
    impact.impactOccurred()
  }
  
  private func triggerNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    notificationGenerator.notificationOccurred(type)
  }
}
