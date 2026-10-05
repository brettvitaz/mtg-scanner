#if DEBUG
import SwiftData
import SwiftUI

/// Debug-only route that photographs the Results tab scanned-card badge.
///
/// Opens on Library rather than Results: opening Results is what clears the tally, so a
/// route that lands there would photograph an empty tab bar. Scan cannot be used for the
/// same check because the Simulator has no camera.
public struct ResultsBadgeFixtureView: View {
    private let appModel = AppModel()
    private let libraryViewModel = LibraryViewModel()
    private let collection = CardCollection(name: "Trade Binder")
    private let deck = Deck(name: "Commander Deck")
    private let container: ModelContainer?
    private let setupError: String?

    /// - Parameter count: the scanned-card tally to show, e.g. 7, or 1_000 to show "999+".
    public init(count: Int) {
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(collection)
            container.mainContext.insert(deck)
            try container.mainContext.save()
            appModel.modelContext = container.mainContext
            appModel.scanSessionCount = count
            libraryViewModel.modelContext = container.mainContext
            self.container = container
            setupError = nil
        } catch {
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            RootTabView(initialTab: 2)
                .environment(appModel)
                .environment(libraryViewModel)
                .modelContainer(container)
        } else {
            Text(setupError ?? "Unable to load the badge fixture.")
        }
    }
}
#endif
