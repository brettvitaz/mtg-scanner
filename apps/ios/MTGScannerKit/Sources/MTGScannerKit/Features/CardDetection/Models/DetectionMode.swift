/// Operating mode for real-time card detection.
enum DetectionMode: String, CaseIterable, Identifiable {
    /// Detect individual cards laid on a flat surface (up to 9).
    case table
    /// Detect a binder page and subdivide it into a 3×3 card grid.
    case binder
    /// Continuously watch a scanning station bin and auto-capture each new card dropped in.
    case quickScan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .table:     return "Table"
        case .binder:    return "Binder"
        case .quickScan: return "Quick Scan"
        }
    }
}
