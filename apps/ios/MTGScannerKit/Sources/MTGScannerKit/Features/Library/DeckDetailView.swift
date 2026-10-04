import SwiftData
import SwiftUI
import UIKit

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSelecting = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showCopyMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false
    @State private var contextTransferItem: CollectionItem?
    @State private var contextDeleteItem: CollectionItem?
    @State private var showAddCard = false
    @State private var showCSVImport = false
    @State private var showListOperation = false
    @State private var selectedCard: RecognizedCard?
    @State private var showSearch = false

    private var isDeleted: Bool { deck.isDeleted || deck.modelContext == nil }

    private var undoIsBlocked: Bool {
        showCopyMoveSheet || contextTransferItem != nil || showDeleteConfirmation
        || contextDeleteItem != nil || exportFile != nil || showFilterSheet
        || showAddCard || showCSVImport || showListOperation || selectedCard != nil || isDeleted
    }

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: deck.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            CardListTitleHeader(title: isDeleted ? "Deck Removed" : deck.name)
            Group {
                if isDeleted {
                    ContentUnavailableView(
                        "Deck Removed", systemImage: "rectangle.stack",
                        description: Text("Finish the list action to return to Library.")
                    )
                } else if deck.items.isEmpty {
                    emptyState
                } else {
                    cardListWithToolbar
                }
            }
        }
        .cardDeleteUndo(scope: .deck(deck.id), name: deck.name, blocked: undoIsBlocked)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbarBackground(Color.dsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedCard) { card in
            CardDetailView(card: card)
        }
        .toolbar { if !isDeleted { topToolbar } }
        .sheet(isPresented: $showCopyMoveSheet) {
            CopyMoveSheet(items: deck.items.filter { selectedItems.contains($0.id) }) { _ in
                exitSelecting()
            }
        }
        .sheet(item: $contextTransferItem) { item in
            CopyMoveSheet(items: [item]) { _ in
                contextTransferItem = nil
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
        .sheet(isPresented: $showListOperation) {
            CardListOperationView(target: .deck(deck))
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportView(destination: .deck(deck))
        }
        .sheet(isPresented: $showAddCard) {
            AddCardView(confirmTitle: "Add to Deck") { item in
                mergeOrInsert(item, into: deck.items, context: modelContext) {
                    $0.deck = deck
                }
                deck.updatedAt = Date()
            }
        }
        .task(id: isDeleted ? [] : deck.items.map(\.id)) {
            if !isDeleted { await appModel.refreshPrices(for: deck.items) }
        }
        .onChange(of: showListOperation) { _, presented in
            if !presented && isDeleted { dismiss() }
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
                CardListOverflowMenu(
                    items: deck.items,
                    name: deck.name,
                    exportFile: $exportFile,
                    onSelect: enterSelecting,
                    onAdd: { showAddCard = true },
                    onImport: { showCSVImport = true },
                    onListOperation: { showListOperation = true }
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
            Text("Tap Add Card below, or move cards here from the Results tab or a collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Card") { showAddCard = true }
                .buttonStyle(.borderedProminent)
            Button("Apply a List") { showListOperation = true }
                .buttonStyle(.bordered)
            Button("Import CSV") { showCSVImport = true }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var cardListWithToolbar: some View {
        List(selection: $selectedItems) {
            Section {
                ForEach(displayedItems) { cardRowView(for: $0) }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .overlay {
            if displayedItems.isEmpty {
                CardListNoMatchesView(filterState: filterState)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.dsBackground)
        .environment(\.editMode, isSelecting ? .constant(.active) : .constant(.inactive))
        .safeAreaInset(edge: .top, spacing: 0) { cardListHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { bottomActionBar }
        }
    }

    @ViewBuilder
    var cardListHeader: some View {
        if !isSelecting {
            VStack(spacing: 0) {
                if showSearch {
                    ListSearchField(text: $filterState.searchText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                SortFilterChipRow(
                    filterState: filterState,
                    showFilterSheet: $showFilterSheet,
                    displayedItems: displayedItems,
                    totalQuantity: deck.items.totalQuantity
                )
            }
            .background(Color.dsBackground)
        }
    }

    @ViewBuilder
    func cardRowView(for item: CollectionItem) -> some View {
        if isSelecting {
            CollectionItemRow(item: item)
        } else {
            CollectionItemRow(
                item: item,
                showQuantityStepper: true,
                onTransfer: { contextTransferItem = item },
                onDelete: { contextDeleteItem = item },
                onSwipeDelete: { deleteItem(item) },
                onToggleFoil: { toggleFoil(item) },
                onSwipeToggleFoil: { toggleFoil(item) },
                onNavigate: { selectedCard = item.toRecognizedCard() }
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
            actionButton("doc.on.doc", "Copy/Move") { showCopyMoveSheet = true }
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
            Task { await appModel.refreshPrice(for: item) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            deck.updatedAt = Date()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func registerUndo(for items: [CollectionItem]) {
        appModel.deleteUndo.register(items, in: .deck(deck.id))
    }
}
