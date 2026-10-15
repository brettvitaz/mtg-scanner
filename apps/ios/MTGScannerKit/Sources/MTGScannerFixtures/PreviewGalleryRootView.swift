import MTGScannerKit
import SwiftUI

/// Debug-only root view that renders a single named route in full-screen.
///
/// Activated when the app is launched with `-UI_PREVIEW_ROUTE <name>`.
/// Use `make ios-snapshot ROUTE=<name>` to capture a PNG of any route.
///
/// Adding a new route:
/// 1. Add a `case "<name>":` branch below returning the view.
/// 2. Run `make ios-snapshot ROUTE=<name>` to verify and capture.
public struct PreviewGalleryRootView: View {
    let route: String
    @State private var appModel = AppModel()

    public init(route: String) {
        self.route = route
        if route.hasPrefix("result-scan-") || route.hasSuffix("scan-excluded") { Self.cacheResultArtwork() }
        if route.hasPrefix("card-row-") || route.hasPrefix("selection-") { Self.cachePreviewArtwork() }
    }

    private static func cachePreviewArtwork() {
        guard let resource = Bundle.module.url(forResource: "CardPreviewArtwork", withExtension: "jpg"),
              let data = try? Data(contentsOf: resource),
              let url = URL(string: "https://fixtures.invalid/card-preview.jpg"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "image/jpeg"]) else { return }
        URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data),
                                            for: URLRequest(url: url))
    }

    private static func cacheResultArtwork() {
        guard let resource = Bundle.module.url(forResource: "ResultScanSample", withExtension: "jpg"),
              let data = try? Data(contentsOf: resource),
              let url = URL(string: "https://fixtures.invalid/result-artwork.jpg"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "image/jpeg"]) else { return }
        URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data),
                                            for: URLRequest(url: url))
    }

    public var body: some View {
        ZStack { routedContent }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch route {
        case "settings":
            NavigationStack {
                SettingsView()
            }
            .environment(appModel)

        case "scan":
            ZStack {
                FixtureCameraPreviewRepresentable { cards in
                    // Detection count visible in console logs; overlay rendered inside the VC.
                    _ = cards
                }
                .ignoresSafeArea()
            }

        #if DEBUG
        case "scan-count-zero", "scan-count-new", "scan-count-overflow", "scan-count-navigation":
            ScanCountFixtureView(route: route)
        case "result-scan-artwork", "result-scan-image", "result-scan-zoom", "result-scan-edit",
             "result-scan-missing", "collection-scan-excluded", "deck-scan-excluded":
            if let resource = Bundle.module.url(forResource: "ResultScanSample", withExtension: "jpg"),
               let data = try? Data(contentsOf: resource) {
                ResultScanFixtureView(route: route, scanData: data)
            }
        case "card-edit", "card-detail":
            CardEditFixtureView(route: route)
        case "pricing-results", "pricing-collection", "pricing-deck",
             "pricing-large", "pricing-filter", "copy-move", "card-row-preview", "card-row-list":
            CardListPricingFixtureView(route: route)
        case "selection-results", "selection-collection", "selection-deck":
            CardListPricingFixtureView(route: route)
        case "undo-results", "undo-collection", "undo-deck", "undo-empty", "undo-bulk", "undo-navigation":
            CardListPricingFixtureView(route: route)
        case "list-operation", "list-subtract", "list-add-delete", "list-operation-complete",
             "csv-subtract", "list-deleted-collection", "list-deleted-deck":
            CardListOperationFixtureView(route: route)
        case "csv-import", "csv-import-undo", "csv-import-ready", "csv-import-skipped", "csv-import-loading",
             "csv-import-error", "csv-import-empty", "csv-import-large", "csv-import-detail",
             "collection-empty", "deck-empty":
            CSVImportFixtureView(route: route)
        #endif

        case "results":
            ResultsFixtureView()
                .environment(appModel)

        default:
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.largeTitle)
                Text("Unknown route: \(route)")
                    .font(.headline)
                Text("Add a case for \"\(route)\" in PreviewGalleryRootView.swift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}

#Preview("Settings") {
    PreviewGalleryRootView(route: "settings")
}

#Preview("Scan (fixture camera)") {
    PreviewGalleryRootView(route: "scan")
}

#Preview("Results (fixture data)") {
    PreviewGalleryRootView(route: "results")
}

#Preview("Selection Results") {
    PreviewGalleryRootView(route: "selection-results")
}

#Preview("Selection Collection") {
    PreviewGalleryRootView(route: "selection-collection")
}

#Preview("Selection Deck") {
    PreviewGalleryRootView(route: "selection-deck")
}

#Preview("result-scan-artwork") {
    PreviewGalleryRootView(route: "result-scan-artwork")
}

#Preview("result-scan-image") {
    PreviewGalleryRootView(route: "result-scan-image")
}

#Preview("result-scan-zoom") {
    PreviewGalleryRootView(route: "result-scan-zoom")
}

#Preview("result-scan-edit") {
    PreviewGalleryRootView(route: "result-scan-edit")
}

#Preview("result-scan-missing") {
    PreviewGalleryRootView(route: "result-scan-missing")
}

#Preview("collection-scan-excluded") {
    PreviewGalleryRootView(route: "collection-scan-excluded")
}

#Preview("deck-scan-excluded") {
    PreviewGalleryRootView(route: "deck-scan-excluded")
}
