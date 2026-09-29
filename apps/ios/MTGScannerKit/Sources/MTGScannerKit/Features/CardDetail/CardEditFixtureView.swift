#if DEBUG
import SwiftData
import SwiftUI

public struct CardEditFixtureView: View {
    private let item = CollectionItem(title: "Lightning Bolt", edition: "Magic 2010", collectorNumber: "146")
    private let route: String
    private let container: ModelContainer?
    private let appModel = AppModel()

    public init(route: String) {
        self.route = route
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(item)
            try container.mainContext.save()
            self.container = container
        } catch {
            container = nil
        }
    }

    public var body: some View {
        if let container {
            content(container: container).modelContainer(container).environment(appModel)
        } else {
            Text("Unable to load card edit fixture.")
        }
    }

    @ViewBuilder
    private func content(container: ModelContainer) -> some View {
        if route == "card-edit" {
            EditCardView(
                draft: CardEditDraft(card: item.toRecognizedCard()),
                onSave: { $0.save(item: item, context: container.mainContext, merge: $1) },
                requiresMerge: { _ in false }
            )
        } else {
            NavigationStack { CardDetailView(card: item.toRecognizedCard()) }
        }
    }

}
#endif
