import SwiftData
import SwiftUI
import UIKit

struct DeckDetailView: View {
    @Bindable var deck: Deck
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
    @State private var recentlyDeleted: [CollectionItem] = []
    @State private var showFoilConflictAlert = false
    @State private var foilConflictMessage = ""

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
        .onReceive(NotificationCenter.default.publisher(for: .shakeDetected)) { _ in
            undoDelete()
        }
        .navigationTitle(deck.name)
        .navigationDestination(for: RecognizedCard.self) { card in
            CardDetailView(card: card)
        }
        .toolbar { topToolbar }
        .searchable(text: $filterState.searchText, prompt: "Search by title or set")
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
        .confirmationDialog(
            "Delete \(selectedItems.count) card(s)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
        }
        .alert("Can't Toggle Is Foil", isPresented: $showFoilConflictAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foilConflictMessage)
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(activityItem: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterState: filterState, items: deck.items)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No cards in this deck")
                .font(.title3.bold())
            Text("Move cards here from the Results tab or a collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card List

    private var cardListWithToolbar: some View {
        let items = displayedItems
        return VStack(spacing: 0) {
            List(selection: $selectedItems) {
                Section {
                    ForEach(items) { cardRowView(for: $0) }
                } header: { cardListHeader(for: items) }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))

            if isSelecting {
                bottomActionBar
            }
        }
    }

    @ViewBuilder
    private func cardRowView(for item: CollectionItem) -> some View {
        if isSelecting {
            CollectionItemRow(item: item)
        } else {
            NavigationLink(value: item.toRecognizedCard()) {
                CollectionItemRow(
                    item: item,
                    showQuantityStepper: true,
                    onCopy: { contextCopyItem = item },
                    onDelete: { deleteItem(item) },
                    onToggleFoil: { toggleFoil(item) }
                )
            }
        }
    }

    private func cardListHeader(for items: [CollectionItem]) -> some View {
        HStack {
            Text("Cards")
            Spacer()
            if filterState.isFilterActive {
                Text("\(items.totalQuantity) of \(deck.items.totalQuantity) card(s)")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(items.totalQuantity) card(s)")
                    .foregroundStyle(.secondary)
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
                    ExportMenuContent(items: deck.items, name: deck.name, exportFile: $exportFile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
            } else if !deck.items.isEmpty {
                Menu {
                    ExportMenuContent(items: deck.items, name: deck.name, exportFile: $exportFile)
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

    private func actionButton(
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
        recentlyDeleted = items
        for item in items {
            modelContext.delete(item)
        }
        deck.updatedAt = Date()
        exitSelecting()
    }

    func deleteItem(_ item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recentlyDeleted = [item]
        modelContext.delete(item)
        deck.updatedAt = Date()
    }

    func undoDelete() {
        guard !recentlyDeleted.isEmpty else { return }
        for deleted in recentlyDeleted {
            modelContext.insert(deleted)
        }
        recentlyDeleted = []
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

    func toggleFoil(_ item: CollectionItem) {
        guard item.toggleFoilIfNoDuplicate(in: deck.items) else {
            foilConflictMessage = "\(item.title) already exists in this deck with that foil setting."
            showFoilConflictAlert = true
            return
        }
        deck.updatedAt = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
