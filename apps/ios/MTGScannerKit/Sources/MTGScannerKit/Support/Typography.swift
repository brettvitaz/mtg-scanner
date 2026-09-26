import SwiftUI

// Fixed-pt type scale for app UI (not fluid — per design brief).
// PostScript names match the filenames registered in FontRegistry.registerAll().

extension Font {
    static func geist(_ style: GeistStyle) -> Font {
        .custom(style.family, size: style.size)
            .weight(style.weight)
    }

    static func geistMono(_ style: GeistMonoStyle) -> Font {
        .custom(style.family, size: style.size)
            .weight(style.weight)
    }
}

enum GeistStyle {
    case screenTitle    // 22pt/600 — NavigationTitle equivalents
    case sectionHeading // 17pt/600 — section headers
    case cardName       // 15pt/500 — primary list text
    case body           // 13pt/400 — body / metadata
    case caption        // 11pt/400 — small labels

    var size: CGFloat {
        switch self {
        case .screenTitle:    return 22
        case .sectionHeading: return 17
        case .cardName:       return 15
        case .body:           return 13
        case .caption:        return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenTitle, .sectionHeading: return .semibold
        case .cardName:                     return .medium
        case .body, .caption:               return .regular
        }
    }

    var family: String {
        switch weight {
        case .semibold: return "Geist-SemiBold"
        case .medium:   return "Geist-Medium"
        default:        return "Geist-Regular"
        }
    }
}

enum GeistMonoStyle {
    case priceMono      // 13pt/500 — sell/buy prices
    case metaMono       // 11pt/400 — set codes, collector numbers
    case confidenceMono // 11pt/500 — confidence percentages

    var size: CGFloat {
        switch self {
        case .priceMono:      return 13
        case .metaMono:       return 11
        case .confidenceMono: return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .priceMono, .confidenceMono: return .medium
        case .metaMono:                   return .regular
        }
    }

    var family: String {
        weight == .medium ? "GeistMono-Medium" : "GeistMono-Regular"
    }
}
