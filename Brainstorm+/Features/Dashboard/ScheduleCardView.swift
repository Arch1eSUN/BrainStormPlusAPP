import SwiftUI

public struct ScheduleCardView: View {
    public let schedule: Schedule
    
    // Quick time formatter for the top
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()
    
    public init(schedule: Schedule) {
        self.schedule = schedule
    }
    
    // Return a theme color based on schedule type
    private var typeColor: Color {
        let typeStr = schedule.type?.lowercased() ?? "work"
        switch typeStr {
        case "meeting":
            return Color.blue
        case "training":
            return Color.purple
        case "work":
            return Color.Brand.primary // Teal
        default:
            return Color.gray
        }
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left timeline indicator
            VStack {
                Text(timeFormatter.string(from: schedule.startTime))
                    .font(.custom("PlusJakartaSans-Bold", size: 14))
                    .foregroundColor(Color.Brand.text)
                
                Text(timeFormatter.string(from: schedule.endTime))
                    .font(.custom("PlusJakartaSans-Regular", size: 12))
                    .foregroundColor(Color.gray)
                
                Spacer()
            }
            .frame(width: 60)
            
            // The Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(schedule.title)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                        .foregroundColor(Color.Brand.text)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Status Badge
                    if let status = schedule.status, status == "completed" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.Brand.secondary)
                            .font(.system(size: 16))
                    } else if let status = schedule.status, status == "cancelled" {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 16))
                    } else {
                        // scheduled
                        Circle()
                            .fill(Color.Brand.accent)
                            .frame(width: 8, height: 8)
                    }
                }
                
                if let desc = schedule.description, !desc.isEmpty {
                    Text(desc)
                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                        .foregroundColor(Color.Brand.text.opacity(0.7))
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let location = schedule.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.custom("PlusJakartaSans-Medium", size: 12))
                            .foregroundColor(typeColor)
                    }
                    
                    if let type = schedule.type {
                        Label(type.capitalized, systemImage: "briefcase")
                            .font(.custom("PlusJakartaSans-Medium", size: 12))
                            .foregroundColor(typeColor)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            // Liquid Glass effect for Card
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(typeColor.opacity(0.1))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(typeColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Interactive map for future navigation
            HapticManager.shared.trigger(.soft)
        }
    }
}
