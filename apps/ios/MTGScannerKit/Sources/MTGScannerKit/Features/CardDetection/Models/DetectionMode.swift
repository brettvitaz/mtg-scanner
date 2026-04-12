/// Operating mode for real-time card detection.
public enum DetectionMode: String, CaseIterable, Identifiable {
    /// Detect cards laid on a flat surface.
    case scan
    /// Continuously watch a scanning station bin and auto-capture each new card dropped in.
    case auto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scan: return "Scan"
        case .auto: return "Auto"
        }
    }

    public var systemImage: String {
        switch self {
        case .scan: return "camera.viewfinder"
        case .auto: return "camera.viewfinder.badge.automatic"
        }
    }
}
