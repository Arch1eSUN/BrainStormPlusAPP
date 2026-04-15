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
            return Color.Brand.primary // Azure Blue
        case "training":
            return Color.purple
        case "work":
            return Color.Brand.accent // Mint Cyan
        default:
            return Color.gray
        }
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left timeline indicator
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeFormatter.string(from: schedule.startTime))
                    .font(.custom("Outfit-Bold", size: 14))
                    .foregroundColor(Color.Brand.text)
                
                Text(timeFormatter.string(from: schedule.endTime))
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundColor(Color.Brand.textSecondary)
                
                Spacer()
            }
            .frame(width: 70, alignment: .trailing)
            .padding(.top, 4)
            
            // The Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(schedule.title)
                        .font(.custom("Outfit-SemiBold", size: 16))
                        .foregroundColor(Color.Brand.text)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Status Badge
                    if let status = schedule.status, status == "completed" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.green)
                            .font(.system(size: 16))
                    } else if let status = schedule.status, status == "cancelled" {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.Brand.warning)
                            .font(.system(size: 16))
                    } else {
                        // scheduled
                        Circle()
                            .fill(Color.Brand.primary)
                            .frame(width: 8, height: 8)
                    }
                }
                
                if let desc = schedule.description, !desc.isEmpty {
                    Text(desc)
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundColor(Color.gray)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let location = schedule.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.custom("Inter-Medium", size: 12))
                            .foregroundColor(Color.Brand.textSecondary)
                    }
                    
                    if let type = schedule.type {
                        Label(type.capitalized, systemImage: "briefcase.fill")
                            .font(.custom("Inter-Medium", size: 12))
                            .foregroundColor(typeColor)
                    }
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Card Material & Shadow
            .background(Color.Brand.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.03), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Interactive map for future navigation
            HapticManager.shared.trigger(.soft)
        }
    }
}
