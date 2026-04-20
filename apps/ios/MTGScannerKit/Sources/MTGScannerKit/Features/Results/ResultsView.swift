import SwiftData
import SwiftUI
import UIKit

public struct ResultsView: View {
    public init() {}

    @Environment(AppModel.self) private var appModel
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
    @State private var contextCopyItem: CollectionItem?
    @State private var contextDeleteItem: CollectionItem?
    @State private var openSwipeRowID: UUID?

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: inboxItems)
    }

    public var body: some View {
        @Bindable var appModel = appModel
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
                    .environment(appModel)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToSheet(title: "Copy To") { destination in
                copySelectedItems(to: destination)
            }
        }
        .sheet(item: $contextCopyItem) { item in
            MoveToSheet(title: "Copy To") { destination in
                copyItem(item, to: destination)
                contextCopyItem = nil
            }
        }
        .alert("Delete \(selectedItems.count) card(s)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These cards will be removed from Results.")
        }
        .alert("Delete \"\(contextDeleteItem?.title ?? "")\"?", isPresented: Binding(
            get: { contextDeleteItem != nil },
            set: { if !$0 { contextDeleteItem = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let item = contextDeleteItem {
                    deleteItem(item)
                    contextDeleteItem = nil
                }
            }
            Button("Cancel", role: .cancel) { contextDeleteItem = nil }
        } message: {
            Text("This card will be removed from Results.")
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(activityItem: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterState: filterState, items: inboxItems)
        }
        .task(id: inboxItems.map(\.id)) {
            await appModel.fetchMissingPrices(for: inboxItems)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Color.dsTextSecondary)
            Text("No results yet")
                .font(.geist(.sectionHeading))
                .foregroundStyle(Color.dsTextPrimary)
            Text("Scan a card to see recognition results here.")
                .font(.geist(.body))
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
    }

    // MARK: - Card List

    private var cardListWithToolbar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItems) {
                Section {
                    ForEach(displayedItems) { cardRowView(for: $0) }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: { cardListHeader }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.dsBackground)
            .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))

            if isSelecting {
                bottomActionBar
            }
        }
        .background(Color.dsBackground)
    }

    @ViewBuilder
    private func cardRowView(for item: CollectionItem) -> some View {
        if isSelecting {
            CollectionItemRow(item: item)
        } else {
            CollectionItemRow(
                item: item,
                onCopy: { contextCopyItem = item },
                onDelete: { contextDeleteItem = item },
                onSwipeDelete: { deleteItem(item) },
                onToggleFoil: { toggleFoil(item) },
                onSwipeToggleFoil: { toggleFoil(item) },
                onNavigate: { appModel.resultsNavigationPath.append(item.toRecognizedCard()) },
                openRowID: $openSwipeRowID
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { toggleFoil(item) })
        }
    }

    private var cardListHeader: some View {
        HStack {
            Text("SCANNED CARDS")
                .font(.geist(.caption))
                .foregroundStyle(Color.dsTextSecondary)
                .textCase(nil)
            Spacer()
            if filterState.isFilterActive {
                Text("\(displayedItems.totalQuantity) of \(inboxItems.totalQuantity) card(s)")
                    .font(.geist(.caption))
                    .foregroundStyle(Color.dsTextSecondary)
            } else {
                Text("\(displayedItems.totalQuantity) card(s)")
                    .font(.geist(.caption))
                    .foregroundStyle(Color.dsTextSecondary)
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
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export results")
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Exit selection mode")
            } else if !inboxItems.isEmpty {
                Menu {
                    ExportMenuContent(items: inboxItems, name: "results", exportFile: $exportFile)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export results")
                Button("Select") { enterSelecting() }
                FilterSortToolbar(filterState: filterState, showFilterSheet: $showFilterSheet)
            }
        }
    }

}

// MARK: - Bottom Action Bar

private extension ResultsView {
    var bottomActionBar: some View {
        HStack {
            actionButton("doc.on.doc", "Copy") { showMoveSheet = true }
            Spacer()
            actionButton("sparkles", "Toggle Foil") { toggleSelectedFoil() }
            Spacer()
            actionButton("trash", "Delete", role: .destructive) { showDeleteConfirmation = true }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(.bar)
    }

    func actionButton(
        _ icon: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            guard !selectedItems.isEmpty else { return }
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.caption2)
            }
        }
        .disabled(selectedItems.isEmpty)
    }
}

// MARK: - Actions

private extension ResultsView {
    func refetchPrice(for item: CollectionItem) async {
        let requestedFoil = item.foil
        guard let price = try? await appModel.fetchPrice(
            name: item.title, scryfallId: item.scryfallId, isFoil: requestedFoil
        ) else {
            print("[ResultsView] refetchPrice failed for \(item.title)")
            return
        }
        guard item.foil == requestedFoil else { return }
        item.priceRetail = price.priceRetail
        item.priceBuy = price.priceBuy
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
        registerUndo(for: items)
        for item in items {
            modelContext.delete(item)
        }
        exitSelecting()
    }

    func deleteItem(_ item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        registerUndo(for: [item])
        modelContext.delete(item)
    }

    func copyItem(_ item: CollectionItem, to destination: MoveDestination) {
        let copy = item.duplicate()
        switch destination {
        case .collection(let collection):
            mergeOrInsert(copy, into: collection.items, context: modelContext) {
                $0.collection = collection
            }
            collection.updatedAt = Date()
        case .deck(let deck):
            mergeOrInsert(copy, into: deck.items, context: modelContext) {
                $0.deck = deck
            }
            deck.updatedAt = Date()
        }
    }

    func toggleFoil(_ item: CollectionItem) {
        item.toggleFoilUnconditionally()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await refetchPrice(for: item) }
    }

    func toggleSelectedFoil() {
        let items = inboxItems.filter { selectedItems.contains($0.id) }
        for item in items {
            item.toggleFoilUnconditionally()
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let fetchRequests = items.map { PriceFetchRequest(item: $0) }
        Task {
            let results = await fetchPrices(for: fetchRequests)
            for (id, price) in results {
                guard
                    let price,
                    let item = items.first(where: { $0.id == id }),
                    item.foil == fetchRequests.first(where: { $0.id == id })?.isFoil
                else { continue }
                item.priceRetail = price.priceRetail
                item.priceBuy = price.priceBuy
            }
        }
    }

    func fetchPrices(for requests: [PriceFetchRequest]) async -> [(UUID, CardPrice?)] {
        await withTaskGroup(of: (UUID, CardPrice?).self) { group in
            for req in requests {
                group.addTask {
                    let price = try? await self.appModel.fetchPrice(
                        name: req.name, scryfallId: req.scryfallId, isFoil: req.isFoil
                    )
                    return (req.id, price)
                }
            }
            var collected: [(UUID, CardPrice?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
    }

    func registerUndo(for items: [CollectionItem]) {
        let deletedItems = items
        appModel.registerUndoAction {
            for item in deletedItems {
                modelContext.insert(item)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
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
