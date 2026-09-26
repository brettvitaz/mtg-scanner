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
    }

    public var body: some View {
        ZStack {
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
