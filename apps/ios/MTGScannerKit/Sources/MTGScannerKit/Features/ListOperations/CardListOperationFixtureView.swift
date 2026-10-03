#if DEBUG
import SwiftData
import SwiftUI

public struct CardListOperationFixtureView: View {
    private let container: ModelContainer?
    private let viewModel: CardListOperationViewModel?
    private let error: String?
    private let route: String
    private let appModel = AppModel()

    public init(route: String) {
        self.route = route
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let model = try Self.prepare(route, context: container.mainContext)
            self.container = container
            viewModel = model
            error = nil
        } catch {
            container = nil
            viewModel = nil
            self.error = error.localizedDescription
        }
    }

    public var body: some View {
        if let container, let viewModel {
            Group {
                if route == "list-deleted-collection" || route == "list-deleted-deck" {
                    deletedDetail(viewModel.tool)
                } else if route == "csv-subtract" {
                    NavigationStack {
                        CSVOperationReviewScreen(viewModel: viewModel) {}
                    }
                } else {
                    CardListOperationView(target: viewModel.target, viewModel: viewModel)
                }
            }
            .modelContainer(container)
            .environment(appModel)
        } else {
            Text(error ?? "Unable to load list operation fixture.")
        }
    }

    @ViewBuilder
    private func deletedDetail(_ list: CardListReference?) -> some View {
        NavigationStack {
            switch list {
            case .collection(let collection): CollectionDetailView(collection: collection)
            case .deck(let deck): DeckDetailView(deck: deck)
            case nil: Text("Missing deleted tool fixture.")
            }
        }
    }

    private static func prepare(_ route: String, context: ModelContext) throws -> CardListOperationViewModel {
        let target = CardListReference.collection(CardCollection(name: "Main Collection"))
        let tool: CardListReference = route == "list-deleted-deck"
            ? .deck(Deck(name: "sell")) : .collection(CardCollection(name: "sell"))
        target.insert(in: context)
        tool.insert(in: context)
        add("Lightning Bolt", quantity: 30, to: target, context: context)
        add("Sol Ring", quantity: 8, to: target, context: context)
        add("Lightning Bolt", quantity: 32, to: tool, context: context)
        add("Sol Ring", quantity: 8, to: tool, context: context)
        context.insert(Deck(name: "Commander Deck"))
        try context.save()
        let model = CardListOperationViewModel(
            target: target, csvItems: route == "csv-subtract" ? tool.items.map(CardItemSnapshot.init) : nil,
            csvName: route == "csv-subtract" ? "sell.csv" : nil,
            operation: ["list-operation", "list-add-delete"].contains(route) ? .add : .subtract
        )
        if route != "list-operation", route != "csv-subtract" { model.chooseTool(tool) }
        model.deleteTool = ["list-add-delete", "list-deleted-collection", "list-deleted-deck"].contains(route)
        if route != "list-operation" { model.refresh() }
        if ["list-operation-complete", "list-deleted-collection", "list-deleted-deck"].contains(route) {
            model.apply(context: context, commit: context.save)
        }
        return model
    }

    private static func add(_ name: String, quantity: Int, to list: CardListReference, context: ModelContext) {
        let item = CollectionItem(
            title: name, edition: "Commander Masters", collectorNumber: name == "Sol Ring" ? "396" : "242",
            scryfallId: name, quantity: quantity
        )
        list.assign(item)
        context.insert(item)
    }
}

#Preview("Subtract sale list") {
    CardListOperationFixtureView(route: "list-subtract")
}
#endif
