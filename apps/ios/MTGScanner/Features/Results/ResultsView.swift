import SwiftData
import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<CollectionItem> { $0.collection == nil && $0.deck == nil },
        sort: \CollectionItem.addedAt,
        order: .reverse
    )
    private var inboxItems: [CollectionItem]

    @State private var isSelecting = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: inboxItems)
    }

    var body: some View {
        NavigationStack(path: $appModel.resultsNavigationPath) {
            Group {
                if inboxItems.isEmpty {
                    emptyState
                } else {
                    cardListWithToolbar
                }
            }
            .navigationTitle("Results")
            .toolbar { topToolbar }
            .searchable(text: $filterState.searchText, prompt: "Search by title or set")
            .navigationDestination(for: RecognizedCard.self) { card in
                CardDetailView(card: card)
                    .environmentObject(appModel)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToSheet(title: "Copy To") { destination in
                copySelectedItems(to: destination)
            }
        }
        .confirmationDialog(
            "Delete \(selectedItems.count) card(s)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(activityItem: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterState: filterState, items: inboxItems)
        }
        .task(id: inboxItems.map(\.id)) {
            await fetchMissingPrices(for: inboxItems)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No results yet")
                .font(.title3.bold())
            Text("Scan a card to see recognition results here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card List

    private var cardListWithToolbar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItems) {
                Section {
                    ForEach(displayedItems) { item in
                        if isSelecting {
                            CollectionItemRow(item: item)
                        } else {
                            NavigationLink(value: item.toRecognizedCard()) {
                                CollectionItemRow(item: item)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Scanned Cards")
                        Spacer()
                        if filterState.isFilterActive {
                            Text("\(displayedItems.totalQuantity) of \(inboxItems.totalQuantity) card(s)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(displayedItems.totalQuantity) card(s)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))

            if isSelecting {
                bottomActionBar
            }
        }
    }

    // MARK: - Top Toolbar

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button("Select All") { selectAll() }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                Menu {
                    ExportMenuContent(items: inboxItems, name: "results", exportFile: $exportFile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
            } else if !inboxItems.isEmpty {
                Menu {
                    ExportMenuContent(items: inboxItems, name: "results", exportFile: $exportFile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button("Select") { enterSelecting() }
                FilterSortToolbar(filterState: filterState, showFilterSheet: $showFilterSheet)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            Button {
                guard !selectedItems.isEmpty else { return }
                showMoveSheet = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy").font(.caption2)
                }
            }
            .disabled(selectedItems.isEmpty)

            Spacer()

            Button(role: .destructive) {
                guard !selectedItems.isEmpty else { return }
                showDeleteConfirmation = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "trash")
                    Text("Delete").font(.caption2)
                }
            }
            .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(.bar)
    }

}

// MARK: - Actions

private extension ResultsView {
    func fetchMissingPrices(for items: [CollectionItem]) async {
        for item in items where item.priceRetail == nil && item.priceBuy == nil {
            guard let price = try? await appModel.fetchPrice(
                name: item.title, scryfallId: item.scryfallId, isFoil: item.foil
            ) else {
                print("[ResultsView] fetchPrice failed for \(item.title)")
                continue
            }
            item.priceRetail = price.priceRetail
            item.priceBuy = price.priceBuy
        }
    }

    func enterSelecting() {
        selectedItems = []
        isSelecting = true
    }

    func exitSelecting() {
        isSelecting = false
        selectedItems = []
    }

    func selectAll() {
        selectedItems = Set(displayedItems.map(\.id))
    }

    func copySelectedItems(to destination: MoveDestination) {
        let items = inboxItems.filter { selectedItems.contains($0.id) }
        switch destination {
        case .collection(let collection):
            for item in items {
                let copy = item.duplicate()
                mergeOrInsert(copy, into: collection.items, context: modelContext) {
                    $0.collection = collection
                }
            }
            collection.updatedAt = Date()
        case .deck(let deck):
            for item in items {
                let copy = item.duplicate()
                mergeOrInsert(copy, into: deck.items, context: modelContext) {
                    $0.deck = deck
                }
            }
            deck.updatedAt = Date()
        }
        exitSelecting()
    }

    func deleteSelectedItems() {
        let items = inboxItems.filter { selectedItems.contains($0.id) }
        for item in items {
            modelContext.delete(item)
        }
        exitSelecting()
    }
}

// MARK: - Hashable conformance for NavigationLink

extension RecognizedCard: Hashable {
    static func == (lhs: RecognizedCard, rhs: RecognizedCard) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
