import SwiftData
import SwiftUI
import UIKit

struct CollectionDetailView: View {
    @Bindable var collection: CardCollection
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false
    @State private var contextCopyItem: CollectionItem?
    @State private var contextDeleteItem: CollectionItem?

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: collection.items)
    }

    var body: some View {
        Group {
            if collection.items.isEmpty {
                emptyState
            } else {
                cardListWithToolbar
            }
        }
        .navigationTitle(collection.name)
        .navigationDestination(for: RecognizedCard.self) { card in
            CardDetailView(card: card)
        }
        .toolbar { topToolbar }
        .searchable(text: $filterState.searchText, prompt: "Search by title or set")
        .sheet(isPresented: $showMoveSheet) {
            MoveToSheet(title: "Copy To Deck") { destination in
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
            Text("These cards will be removed from the collection.")
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
            Text("This card will be removed from the collection.")
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(activityItem: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterState: filterState, items: collection.items)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No cards in this collection")
                .font(.title3.bold())
            Text("Move cards here from the Results tab.")
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
                    onDelete: { contextDeleteItem = item }
                )
            }
        }
    }

    private func cardListHeader(for items: [CollectionItem]) -> some View {
        HStack {
            Text("Cards")
            Spacer()
            if filterState.isFilterActive {
                Text("\(items.totalQuantity) of \(collection.items.totalQuantity) card(s)")
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
                    ExportMenuContent(items: collection.items, name: collection.name, exportFile: $exportFile)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
            } else if !collection.items.isEmpty {
                Menu {
                    ExportMenuContent(items: collection.items, name: collection.name, exportFile: $exportFile)
                } label: {
                    Image(systemName: "square.and.arrow.up")
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
                    Image(systemName: "rectangle.stack")
                    Text("Copy to Deck").font(.caption2)
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

private extension CollectionDetailView {
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
        let items = collection.items.filter { selectedItems.contains($0.id) }
        switch destination {
        case .collection(let targetCollection):
            for item in items {
                let copy = item.duplicate()
                mergeOrInsert(copy, into: targetCollection.items, context: modelContext) {
                    $0.collection = targetCollection
                }
            }
            targetCollection.updatedAt = Date()
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
        let items = collection.items.filter { selectedItems.contains($0.id) }
        registerUndo(for: items)
        for item in items {
            modelContext.delete(item)
        }
        collection.updatedAt = Date()
        exitSelecting()
    }

    func deleteItem(_ item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        registerUndo(for: [item])
        modelContext.delete(item)
        collection.updatedAt = Date()
    }

    func copyItem(_ item: CollectionItem, to destination: MoveDestination) {
        let copy = item.duplicate()
        switch destination {
        case .collection(let targetCollection):
            mergeOrInsert(copy, into: targetCollection.items, context: modelContext) {
                $0.collection = targetCollection
            }
            targetCollection.updatedAt = Date()
        case .deck(let deck):
            mergeOrInsert(copy, into: deck.items, context: modelContext) {
                $0.deck = deck
            }
            deck.updatedAt = Date()
        }
    }

    func registerUndo(for items: [CollectionItem]) {
        let deletedItems = items
        let deletedCollection = collection
        appModel.registerUndoAction {
            for item in deletedItems {
                modelContext.insert(item)
            }
            deletedCollection.updatedAt = Date()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
