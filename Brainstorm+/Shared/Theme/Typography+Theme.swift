import SwiftUI

public extension Font {
    struct ZY {
        // Base Font Names
        // Matching "Outfit" for headings and "Inter" / system for body
        public static let headingName = "Outfit"
        
        // Dynamic Type Styles
        public static var h1: Font {
            .custom(headingName, size: 32, relativeTo: .largeTitle).weight(.bold)
        }
        
        public static var h2: Font {
            .custom(headingName, size: 24, relativeTo: .title).weight(.bold)
        }
        
        public static var h3: Font {
            .custom(headingName, size: 20, relativeTo: .title2).weight(.semibold)
        }
        
        public static var body: Font {
            .system(.body, design: .default) // System closely matches Inter
        }
        
        public static var bodySemiBold: Font {
            .system(.body, design: .default).weight(.semibold)
        }
        
        public static var caption: Font {
            .system(.caption, design: .default)
        }
        
        public static var captionMedium: Font {
            .system(.caption, design: .default).weight(.medium)
        }
    }
}
