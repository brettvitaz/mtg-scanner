#if DEBUG
import SwiftData
import SwiftUI

/// Simulator-only fixture for checking import review and empty destination entry points.
public struct CSVImportFixtureView: View {
    private let route: String
    private let collection = CardCollection(name: "Trade Binder")
    private let deck = Deck(name: "Commander Deck")
    private let appModel = AppModel()
    private let viewModel = CSVImportViewModel()
    private let container: ModelContainer?
    private let setupError: String?

    public init(route: String) {
        self.route = route
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(collection)
            container.mainContext.insert(deck)
            try container.mainContext.save()
            try Self.prepareReview(viewModel, route: route)
            self.container = container
            setupError = nil
        } catch {
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            content.modelContainer(container).environment(appModel)
        } else {
            Text(setupError ?? "Unable to load import fixture.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case "collection-empty": NavigationStack { CollectionDetailView(collection: collection) }
        case "deck-empty": NavigationStack { DeckDetailView(deck: deck) }
        case "csv-import-detail":
            NavigationStack { CSVImportRowDetail(rowID: 3, viewModel: viewModel) }
        default: CSVImportView(
            destination: .collection(collection), viewModel: viewModel,
            operation: route == "csv-import-subtract" ? .subtract : .add
        )
        }
    }

    private static func prepareReview(_ viewModel: CSVImportViewModel, route: String) throws {
        let csv = "title,edition,quantity,foil,collector_number\n"
            + "Lightning Bolt,Magic 2010,4,false,146\nForest,Magic 2010,2,false,\n"
            + "Counterspell,Magic 2010,0,false,\n"
        viewModel.filename = "trade-binder.csv"
        viewModel.rows = try CSVImportService().parse(data: Data(csv.utf8))
        let data = Data("""
            {"name":"Lightning Bolt","set_code":"M10","set_name":"Magic 2010", "collector_number":"146"}
            """.utf8)
        viewModel.rows[0].printing = try JSONDecoder().decode(CardPrinting.self, from: data)
        viewModel.rows[1].issue = "Choose a printing. No unique match was found."
        configureState(viewModel, route: route)
    }

    private static func configureState(_ viewModel: CSVImportViewModel, route: String) {
        switch route {
        case "csv-import-undo": viewModel.skipAllUnmatched()
        case "csv-import-ready", "csv-import-subtract": viewModel.rows = viewModel.readyRows
        case "csv-import-skipped":
            for index in viewModel.rows.indices { viewModel.rows[index].isSkipped = true }
        case "csv-import-loading":
            viewModel.isLoading = true
            viewModel.processedRows = 1
        case "csv-import-error":
            viewModel.rows = []
            viewModel.errorMessage = "Missing required columns: edition."
        case "csv-import-empty":
            viewModel.rows = []
            viewModel.filename = ""
        case "csv-import-large":
            let matched = viewModel.rows[0]
            viewModel.rows += (5...154).map { number in
                CSVImportRow(id: number, title: matched.title, record: matched.record, printing: matched.printing)
            }
        default: break
        }
    }
}
#endif
