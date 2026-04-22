import SwiftData
import SwiftUI
import UIKit

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showMoveSheet = false
    @State private var showCopySheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false
    @State private var contextCopyItem: CollectionItem?
    @State private var contextMoveItem: CollectionItem?
    @State private var contextDeleteItem: CollectionItem?
    @State private var showAddCard = false
    @State private var openSwipeRowID: UUID?
    @State private var selectedCard: RecognizedCard?
    @State private var showSearch = false

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: deck.items)
    }

    var body: some View {
        Group {
            if deck.items.isEmpty {
                emptyState
            } else {
                cardListWithToolbar
            }
        }
        .navigationTitle(deck.name)
        .navigationDestination(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .toolbar { topToolbar }
        .sheet(isPresented: $showMoveSheet) {
            MoveToSheet(title: "Move To Collection") { destination in
                moveSelectedItems(to: destination)
            }
        }
        .sheet(isPresented: $showCopySheet) {
            MoveToSheet(title: "Copy To Collection") { destination in
                copySelectedItems(to: destination)
            }
        }
        .sheet(item: $contextCopyItem) { item in
            MoveToSheet(title: "Copy To") { destination in
                copyItem(item, to: destination)
                contextCopyItem = nil
            }
        }
        .sheet(item: $contextMoveItem) { item in
            MoveToSheet(title: "Move To") { destination in
                moveItem(item, to: destination)
                contextMoveItem = nil
            }
        }
        .alert("Delete \(selectedItems.count) card(s)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These cards will be removed from the deck.")
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
            Text("This card will be removed from the deck.")
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(activityItem: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterState: filterState, items: deck.items)
        }
        .sheet(isPresented: $showAddCard) {
            AddCardView(confirmTitle: "Add to Deck") { item in
                mergeOrInsert(item, into: deck.items, context: modelContext) {
                    $0.deck = deck
                }
                deck.updatedAt = Date()
            }
        }
        .task(id: deck.items.map(\.id)) {
            await appModel.fetchMissingPrices(for: deck.items)
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
                    ExportMenuContent(items: deck.items, name: deck.name, exportFile: $exportFile)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export deck")
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Exit selection mode")
            } else if !deck.items.isEmpty {
                Button { toggleSearch() } label: {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(showSearch ? "Close search" : "Search")
                Button { showAddCard = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add card manually")
                CardListOverflowMenu(
                    items: deck.items,
                    name: deck.name,
                    exportFile: $exportFile,
                    onSelect: enterSelecting
                )
            }
        }
    }

}

// MARK: - Card List + Empty State

private extension DeckDetailView {
    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No cards in this deck")
                .font(.title3.bold())
            Text("Add cards using the + button, or move cards here from the Results tab or a collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Card") { showAddCard = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var cardListWithToolbar: some View {
        let items = displayedItems
        return VStack(spacing: 0) {
            if !isSelecting {
                if showSearch {
                    ListSearchField(text: $filterState.searchText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                SortFilterChipRow(
                    filterState: filterState,
                    showFilterSheet: $showFilterSheet,
                    displayedQuantity: items.totalQuantity,
                    totalQuantity: deck.items.totalQuantity
                )
            }
            List(selection: $selectedItems) {
                Section {
                    ForEach(items) { cardRowView(for: $0) }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.dsBackground)
            .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))

            if isSelecting { bottomActionBar }
        }
        .background(Color.dsBackground)
    }

    @ViewBuilder
    func cardRowView(for item: CollectionItem) -> some View {
        if isSelecting {
            CollectionItemRow(item: item)
        } else {
            CollectionItemRow(
                item: item,
                showQuantityStepper: true,
                onCopy: { contextCopyItem = item },
                onMove: { contextMoveItem = item },
                onDelete: { contextDeleteItem = item },
                onSwipeDelete: { deleteItem(item) },
                onToggleFoil: { toggleFoil(item) },
                onSwipeToggleFoil: { toggleFoil(item) },
                onNavigate: { selectedCard = item.toRecognizedCard() },
                openRowID: $openSwipeRowID
            )
        }
    }

    func toggleSearch() {
        withAnimation(.smooth(duration: 0.2)) {
            showSearch.toggle()
            if !showSearch { filterState.searchText = "" }
        }
    }
}

// MARK: - Bottom Action Bar

private extension DeckDetailView {
    var bottomActionBar: some View {
        HStack {
            actionButton("folder", "Move") { showMoveSheet = true }
            Spacer()
            actionButton("doc.on.doc", "Copy") { showCopySheet = true }
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

extension DeckDetailView {
    func enterSelecting() {
        showSearch = false
        filterState.searchText = ""
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

    func moveSelectedItems(to destination: MoveDestination) {
        let items = deck.items.filter { selectedItems.contains($0.id) }
        switch destination {
        case .collection(let collection):
            for item in items {
                item.deck = nil
                item.collection = collection
            }
            collection.updatedAt = Date()
        case .deck(let targetDeck):
            for item in items {
                item.collection = nil
                item.deck = targetDeck
            }
            targetDeck.updatedAt = Date()
        }
        deck.updatedAt = Date()
        exitSelecting()
    }

    func copySelectedItems(to destination: MoveDestination) {
        let items = deck.items.filter { selectedItems.contains($0.id) }
        switch destination {
        case .collection(let collection):
            for item in items {
                let copy = item.duplicate()
                mergeOrInsert(copy, into: collection.items, context: modelContext) {
                    $0.collection = collection
                }
            }
            collection.updatedAt = Date()
        case .deck(let targetDeck):
            for item in items {
                let copy = item.duplicate()
                mergeOrInsert(copy, into: targetDeck.items, context: modelContext) {
                    $0.deck = targetDeck
                }
            }
            targetDeck.updatedAt = Date()
        }
        exitSelecting()
    }

    func deleteSelectedItems() {
        let items = deck.items.filter { selectedItems.contains($0.id) }
        registerUndo(for: items)
        for item in items {
            modelContext.delete(item)
        }
        deck.updatedAt = Date()
        exitSelecting()
    }

    func deleteItem(_ item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        registerUndo(for: [item])
        modelContext.delete(item)
        deck.updatedAt = Date()
    }

    func toggleFoil(_ item: CollectionItem) {
        if item.toggleFoilIfNoDuplicate(in: deck.items) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            deck.updatedAt = Date()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func copyItem(_ item: CollectionItem, to destination: MoveDestination) {
        let copy = item.duplicate()
        switch destination {
        case .collection(let collection):
            mergeOrInsert(copy, into: collection.items, context: modelContext) {
                $0.collection = collection
            }
            collection.updatedAt = Date()
        case .deck(let targetDeck):
            mergeOrInsert(copy, into: targetDeck.items, context: modelContext) {
                $0.deck = targetDeck
            }
            targetDeck.updatedAt = Date()
        }
    }

    func moveItem(_ item: CollectionItem, to destination: MoveDestination) {
        switch destination {
        case .collection(let collection):
            item.deck = nil
            item.collection = collection
            collection.updatedAt = Date()
        case .deck(let targetDeck):
            item.collection = nil
            item.deck = targetDeck
            targetDeck.updatedAt = Date()
        }
        deck.updatedAt = Date()
    }

    func registerUndo(for items: [CollectionItem]) {
        let deletedItems = items
        let deletedDeck = deck
        appModel.registerUndoAction {
            for item in deletedItems {
                modelContext.insert(item)
            }
            deletedDeck.updatedAt = Date()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
