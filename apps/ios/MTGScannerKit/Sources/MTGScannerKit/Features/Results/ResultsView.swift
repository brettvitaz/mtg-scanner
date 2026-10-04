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
    @State private var showCopyMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?
    @State private var filterState = CardFilterState()
    @State private var showFilterSheet = false
    @State private var contextTransferItem: CollectionItem?
    @State private var contextDeleteItem: CollectionItem?
    @State private var showSearch = false

    private var undoIsBlocked: Bool {
        showCopyMoveSheet || contextTransferItem != nil || showDeleteConfirmation
        || contextDeleteItem != nil || exportFile != nil || showFilterSheet
        || !appModel.resultsNavigationPath.isEmpty
    }

    private var displayedItems: [CollectionItem] {
        filterState.apply(to: inboxItems)
    }

    public var body: some View {
        @Bindable var appModel = appModel
        NavigationStack(path: $appModel.resultsNavigationPath) {
            VStack(spacing: 0) {
                CardListTitleHeader(title: "Results")
                Group {
                    if inboxItems.isEmpty {
                        emptyState
                    } else {
                        cardListWithToolbar
                    }
                }
            }
            .cardDeleteUndo(scope: .results, name: "Results", blocked: undoIsBlocked)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isSelecting)
            .toolbarBackground(Color.dsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { topToolbar }
            .navigationDestination(for: RecognizedCard.self) { card in
                CardDetailView(card: card)
                    .environment(appModel)
            }
        }
        .sheet(isPresented: $showCopyMoveSheet) {
            CopyMoveSheet(items: inboxItems.filter { selectedItems.contains($0.id) }) { _ in
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
            await appModel.refreshPrices(for: inboxItems)
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
    private var cardListHeader: some View {
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
                    totalQuantity: inboxItems.totalQuantity
                )
            }
            .background(Color.dsBackground)
        }
    }

    @ViewBuilder
    private func cardRowView(for item: CollectionItem) -> some View {
        if isSelecting {
            CollectionItemRow(item: item)
        } else {
            CollectionItemRow(
                item: item,
                onTransfer: { contextTransferItem = item },
                onDelete: { contextDeleteItem = item },
                onSwipeDelete: { deleteItem(item) },
                onToggleFoil: { toggleFoil(item) },
                onSwipeToggleFoil: { toggleFoil(item) },
                onNavigate: { appModel.resultsNavigationPath.append(item.toRecognizedCard()) }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { toggleFoil(item) })
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
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        showSearch.toggle()
                        if !showSearch { filterState.searchText = "" }
                    }
                } label: {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(showSearch ? "Close search" : "Search")
                CardListOverflowMenu(
                    items: inboxItems,
                    name: "results",
                    exportFile: $exportFile,
                    onSelect: enterSelecting
                )
            }
        }
    }

}

// MARK: - Bottom Action Bar

private extension ResultsView {
    var bottomActionBar: some View {
        HStack {
            actionButton("doc.on.doc", "Copy/Move") { showCopyMoveSheet = true }
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

    func toggleFoil(_ item: CollectionItem) {
        item.toggleFoilUnconditionally()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await appModel.refreshPrice(for: item) }
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
                    let request = fetchRequests.first(where: { $0.id == id })
                else { continue }
                item.apply(price: price, matching: request)
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
        appModel.deleteUndo.register(items, in: .results)
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
