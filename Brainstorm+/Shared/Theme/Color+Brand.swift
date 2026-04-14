import SwiftUI

public extension Color {
  struct Brand {
    // MARK: - Primary Colors
    /// Primary Teal - Main brand color for interactive elements
    public static let primary = Color(hex: "#0D9488")
    
    /// Secondary Teal - Supporting brand color for emphasis
    public static let secondary = Color(hex: "#14B8A6")
    
    // MARK: - Accent Colors
    /// CTA Orange - High-priority actions and calls-to-action
    public static let accent = Color(hex: "#F97316")
    
    // MARK: - Semantic Colors
    /// Background - Light surface for content areas
    public static let background = Color(hex: "#F0FDFA")
    
    /// Text - Primary text color for readability
    public static let text = Color(hex: "#134E4A")
  }
}
