/// Operating mode for real-time card detection.
enum DetectionMode: String, CaseIterable, Identifiable {
    /// Detect individual cards laid on a flat surface (up to 9).
    case table
    /// Detect a binder page and subdivide it into a 3×3 card grid.
    case binder

    var id: String { rawValue }
}
