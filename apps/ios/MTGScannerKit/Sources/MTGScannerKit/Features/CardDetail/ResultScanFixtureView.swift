#if DEBUG
import SwiftData
import SwiftUI

public struct ResultScanFixtureView: View {
    private let route: String
    private let container: ModelContainer?
    private let item: CollectionItem
    private let appModel = AppModel()
    private let failure: String?

    public init(route: String, scanData: Data) {
        self.route = route
        let card = RecognizedCard(title: "Teferi’s Protection", edition: "Commander 2017", collectorNumber: "8",
                                  foil: false, confidence: 0.98, setCode: "C17", typeLine: "Instant",
                                  imageUrl: "https://fixtures.invalid/result-artwork.jpg",
                                  cropImageData: scanData.base64EncodedString())
        let item = CollectionItem(from: card)
        self.item = item
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self, RecognitionFeedbackEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            if route != "result-scan-missing" { item.attachResultEvidence(from: card) }
            container.mainContext.insert(item)
            if route == "collection-scan-excluded" {
                let collection = CardCollection(name: "Binder")
                container.mainContext.insert(collection)
                item.clearResultEvidence()
                item.collection = collection
            } else if route == "deck-scan-excluded" {
                let deck = Deck(name: "Deck")
                container.mainContext.insert(deck)
                item.clearResultEvidence()
                item.deck = deck
            }
            try container.mainContext.save()
            self.container = container
            failure = nil
        } catch {
            container = nil
            failure = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            content(container.mainContext).modelContainer(container).environment(appModel)
        } else {
            Text("Unable to load result scan fixture: \(failure ?? "Unknown error")")
        }
    }

    @ViewBuilder
    private func content(_ context: ModelContext) -> some View {
        if route == "result-scan-edit" {
            EditCardView(draft: CardEditDraft(card: item.toRecognizedCard()), scan: item.resultScanImage,
                         initialScanSelected: true,
                         onSave: { $0.save(item: item, context: context, merge: $1) },
                         requiresMerge: { _ in false })
        } else {
            NavigationStack {
                CardDetailView(card: item.toRecognizedCard(), resultScope: route.hasPrefix("result-"),
                               showingScan: route == "result-scan-image" || route == "result-scan-zoom",
                               showImageViewer: route == "result-scan-zoom",
                               initialZoom: route == "result-scan-zoom" ? 3 : 1)
            }
        }
    }
}
#endif
