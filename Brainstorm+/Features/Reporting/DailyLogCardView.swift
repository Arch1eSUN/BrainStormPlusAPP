import SwiftUI

public struct DailyLogCardView: View {
    public let log: DailyLog
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(log.date, style: .date)
                    .font(.headline)
                Spacer()
                if let mood = log.mood {
                    moodTag(mood: mood)
                }
            }
            
            Text(log.content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    @ViewBuilder
    private func moodTag(mood: DailyLog.Mood) -> some View {
        HStack(spacing: 4) {
            Text(moodEmoji(mood))
            Text(mood.rawValue.capitalized)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private func moodEmoji(_ mood: DailyLog.Mood) -> String {
        switch mood {
        case .great: return "🤩"
        case .good: return "😊"
        case .okay: return "😐"
        case .bad: return "😔"
        }
    }
}
