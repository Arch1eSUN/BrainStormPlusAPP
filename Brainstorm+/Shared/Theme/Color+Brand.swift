import SwiftUI

public extension Color {
  struct Brand {
    // MARK: - Primary Colors (Azure Blue)
    /// Azure Blue - Main brand color for interactive elements and primary buttons
    public static let primary = Color(hex: "#0080FF")
    
    /// Primary Light - Backgrounds for primary elements
    public static let primaryLight = Color(hex: "#E0F0FF")
    
    /// Primary Dark - Hover/Pressed states for primary elements
    public static let primaryDark = Color(hex: "#0060CC")
    
    // MARK: - Accent Colors (Mint Cyan)
    /// Mint Cyan - Secondary branding, subtle glowing accents
    public static let accent = Color(hex: "#00E5CC")
    
    /// Mint Cyan Light
    public static let accentLight = Color(hex: "#B3F5EC")
    
    /// Coral Orange - High-priority actions, destructive/warning actions, notifications
    public static let warning = Color(hex: "#FF6B42")
    
    // MARK: - Semantic Colors (Backgrounds & Surfaces)
    /// ZY Paper - Purest light surface for cards
    public static let paper = Color(hex: "#FDFDFC")
    
    /// Surface BG - Base background color (warm-tinted off-white)
    public static let background = Color(hex: "#f5f3f0")
    
    /// Ink Dark - Main text color for maximum readability (not pure black)
    public static let text = Color(hex: "#1B1B18")
    
    /// Ink Light - Secondary text color
    public static let textSecondary = Color(hex: "#2D2D2A")
    
    // MARK: - System/Borders
    /// Light gray for subtle dividers and glass borders
    public static let border = Color.white.opacity(0.65)
  }
}
