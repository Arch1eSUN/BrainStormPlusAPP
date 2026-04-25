import SwiftUI

/// Iter 7 Phase 1.2 — typing indicator strip rendered between message list
/// and the input bar. Visible only when `users` non-empty.
///
/// Visual: 3 dots .symbolEffect(.bounce) + "X 正在输入..." in muted ink.
/// Multiple users → "X、Y 等 N 人正在输入...".
struct TypingIndicator: View {
    let users: [TypingUser]
    @State private var animate = false

    private var label: String {
        switch users.count {
        case 0:  return ""
        case 1:  return "\(users[0].name) 正在输入"
        case 2:  return "\(users[0].name)、\(users[1].name) 正在输入"
        default:
            return "\(users[0].name)、\(users[1].name) 等 \(users.count) 人正在输入"
        }
    }

    var body: some View {
        if users.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: BsSpacing.xs + 2) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(BsColor.brandAzure.opacity(0.65))
                            .frame(width: 5, height: 5)
                            .scaleEffect(animate ? 1.0 : 0.55)
                            .opacity(animate ? 1.0 : 0.4)
                            .animation(
                                .easeInOut(duration: 0.65)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.18),
                                value: animate
                            )
                    }
                }
                .padding(.horizontal, BsSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(BsColor.brandAzure.opacity(0.10))
                )

                Text(label)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onAppear { animate = true }
            .onDisappear { animate = false }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
        }
    }
}
