import Foundation

/// Formats the scanned-card tally shown on the Results tab.
///
/// The tally itself lives on AppModel; this only decides how it is rendered.
enum ScanSessionCounter {

    /// Badge text for a tally. Returns nil at zero so the tab shows a bare icon,
    /// and clamps long counts so the tab bar never reflows.
    static func badgeText(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 999 ? "999+" : "\(count)"
    }
}
