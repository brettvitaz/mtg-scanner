/// Operating mode for real-time card detection.
enum DetectionMode: String, CaseIterable, Identifiable {
    /// Detect cards laid on a flat surface.
    case scan
    /// Continuously watch a scanning station bin and auto-capture each new card dropped in.
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scan: return "Scan"
        case .auto: return "Auto"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "camera.viewfinder"
        case .auto: return "camera.viewfinder.badge.automatic"
        }
    }
}
