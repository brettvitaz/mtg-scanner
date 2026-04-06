import SwiftUI
import UniformTypeIdentifiers

/// Export menu items for embedding in a parent Menu. Exports items as JSON or CSV via share sheet.
/// Usage: Place inside a `Menu { ExportMenuContent(...) }` or alongside other menu items.
struct ExportMenuContent: View {
    let items: [CollectionItem]
    let name: String
    @Binding var exportFile: ExportActivityItem?

    private let exportService = ExportService()

    var body: some View {
        ForEach(ExportFormat.allCases) { format in
            Button {
                if let file = exportService.export(items: items, format: format, name: name) {
                    exportFile = ExportActivityItem(file: file)
                }
            } label: {
                Label("Export as \(format.rawValue)", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Share Sheet

struct ExportActivityItem: Identifiable {
    let id = UUID()
    let file: ExportFile
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItem: ExportActivityItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(activityItem.file.filename)
        try? activityItem.file.data.write(to: fileURL)
        return UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
