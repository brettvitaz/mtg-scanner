import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    @Bindable var collection: CardCollection
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false

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
                    ForEach(items) { item in
                        if isSelecting {
                            CollectionItemRow(item: item)
                        } else {
                            NavigationLink(value: item.toRecognizedCard()) {
                                CollectionItemRow(item: item, showQuantityStepper: true)
                            }
                        }
                    }
                } header: {
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
                    ExportMenuContent(items: collection.items, name: collection.name, exportFile: $exportFile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button { exitSelecting() } label: {
                    Image(systemName: "xmark")
                }
            } else if !collection.items.isEmpty {
                Menu {
                    ExportMenuContent(items: collection.items, name: collection.name, exportFile: $exportFile)
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

    // MARK: - Actions

    private func enterSelecting() {
        selectedItems = []
        isSelecting = true
    }

    private func exitSelecting() {
        isSelecting = false
        selectedItems = []
    }

    private func selectAll() {
        selectedItems = Set(displayedItems.map(\.id))
    }

    private func copySelectedItems(to destination: MoveDestination) {
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

    private func deleteSelectedItems() {
        let items = collection.items.filter { selectedItems.contains($0.id) }
        for item in items {
            modelContext.delete(item)
        }
        collection.updatedAt = Date()
        exitSelecting()
    }
}
