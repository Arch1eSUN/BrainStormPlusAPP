import SwiftUI

/// Top-aligned auto-dismissing error banner. Bind it to an optional String
/// on your ViewModel (typically a `@Published var errorMessage: String?`):
///
///     SomeView()
///         .zyErrorBanner($viewModel.errorMessage)
///
/// When `message` is non-nil the banner slides in; it hides again when the
/// binding becomes nil (either via the explicit dismiss button or the
/// `autoDismissAfter` timer). Repeated messages restart the timer because
/// the inner `task(id:)` is keyed on the payload.
public struct ZYErrorBannerModifier: ViewModifier {
    @Binding var message: String?
    let autoDismissAfter: TimeInterval

    public init(message: Binding<String?>, autoDismissAfter: TimeInterval = 5) {
        self._message = message
        self.autoDismissAfter = autoDismissAfter
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let msg = message {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                    Text(msg)
                        .font(.footnote)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Button {
                        message = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.92))
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                    if message == msg {
                        message = nil
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message)
    }
}

public extension View {
    /// Attach a top-aligned auto-dismissing error banner bound to an optional string.
    /// Pass `autoDismissAfter: 0` to require manual dismissal.
    func zyErrorBanner(_ message: Binding<String?>, autoDismissAfter: TimeInterval = 5) -> some View {
        modifier(ZYErrorBannerModifier(message: message, autoDismissAfter: autoDismissAfter))
    }
}
