#if DEBUG
import SwiftData
import SwiftUI

/// Exercises the badge and real tab navigation without a camera or API connection.
public struct ScanCountFixtureView: View {
    private let appModel = AppModel()
    private let libraryViewModel = LibraryViewModel()
    private let container: ModelContainer?
    private let setupError: String?
    private let isNavigationRoute: Bool

    public init(route: String) {
        isNavigationRoute = route == "scan-count-navigation"
        appModel.selectTab(.settings)
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            appModel.modelContext = container.mainContext
            libraryViewModel.modelContext = container.mainContext
            let count = route == "scan-count-zero" ? 0 : route == "scan-count-overflow" ? 1_000 : 12
            // Older Results items should not produce a badge.
            container.mainContext.insert(CollectionItem(title: "Older card", edition: "Fixture"))
            for index in 0..<count {
                container.mainContext.insert(CollectionItem(title: "Scanned card \(index + 1)", edition: "Fixture"))
                appModel.recordScannedCard()
            }
            try container.mainContext.save()
            self.container = container
            setupError = nil
        } catch {
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            RootTabView()
                .environment(appModel)
                .environment(libraryViewModel)
                .modelContainer(container)
                .overlay {
                    if isNavigationRoute { navigationControls.padding(.horizontal) }
                }
        } else {
            Text(setupError ?? "Unable to load scan count fixture.")
        }
    }

    private var navigationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Results to clear the badge. Leave, then simulate another scan.")
                .font(.footnote)
            HStack {
                Button("Simulate scan") {
                    appModel.modelContext?.insert(CollectionItem(title: "New scan", edition: "Fixture"))
                    appModel.recordScannedCard()
                }
                Button("Open Results") { appModel.shouldShowResults = true }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
    }
}

#Preview("New scanned cards") {
    ScanCountFixtureView(route: "scan-count-new")
}

#Preview("Scan count navigation") {
    ScanCountFixtureView(route: "scan-count-navigation")
}
#endif
