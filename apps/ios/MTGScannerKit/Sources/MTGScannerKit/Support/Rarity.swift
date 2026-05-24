import SwiftUI

/// View-layer rarity classification.
/// Storage stays as `String?` on `CollectionItem`; this enum is constructed at the call site.
enum Rarity: String, CaseIterable {
    case common
    case uncommon
    case rare
    case mythic

    /// Case-insensitive, whitespace-tolerant init. Returns nil for unrecognised strings.
    init?(_ raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        self.init(rawValue: trimmed.lowercased())
    }

    /// Uppercased label for display in meta lines.
    var shortLabel: String { rawValue.uppercased() }

    /// Solid swatch color — used for text labels and badge fills.
    var badgeColor: Color {
        switch self {
        case .mythic:   return Color(uiColor: oklch(0.72, 0.18, 45))
        case .rare:     return Color(uiColor: oklch(0.82, 0.14, 95))
        case .uncommon: return Color(uiColor: oklch(0.65, 0.03, 225))
        case .common:   return .dsTextSecondary
        }
    }

    /// Subtle background tint conveying rarity at a glance.
    func overlayColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .common: return .clear
        default:      return badgeColor.opacity(scheme == .dark ? 0.10 : 0.06)
        }
    }
}
