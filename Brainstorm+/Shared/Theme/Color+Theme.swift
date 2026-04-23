import SwiftUI
import UIKit

public extension Color {
    struct ZY {
        // MARK: - Light Mode Base Colors
        public static let primary = Color(hex: "#0080FF")
        public static let primaryLight = Color(hex: "#E0F0FF")
        public static let primaryDark = Color(hex: "#0060CC")
        
        public static let accent = Color(hex: "#00E5CC")
        public static let accentLight = Color(hex: "#B3F5EC")
        
        public static let ink = Color("ZYInk", bundle: nil) // To support dark mode natively via Asset Catalog, ideally. But we can use dynamic colors.
        public static let inkLight = Color(hex: "#2D2D2A")
        
        public static let paper = Color("ZYPaper") // Same here
        
        public static let surfaceBg = Color(hex: "#F5F3F0")
        
        // MARK: - Semantic Colors
        public static let success = Color(hex: "#10B981")
        public static let warning = Color(hex: "#F59E0B")
        public static let destructive = Color(hex: "#EF4444")
        
        // Dynamic colors supporting Dark Mode (1:1 Web migration)
        public static let dynamicInk = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#FFFFFF")! : UIColor(hex: "#1B1B18")!
        })
        
        public static let dynamicPaper = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#121212")! : UIColor(hex: "#FDFDFC")!
        })
        
        public static let dynamicSurface = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#0A0A0A")! : UIColor(hex: "#F5F3F0")!
        })
    }
}

// Helper for Hex Colors
public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let count = hexSanitized.count
        let r, g, b, a: CGFloat

        if count == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if count == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
