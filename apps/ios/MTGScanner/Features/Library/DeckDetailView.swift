import SwiftData
import SwiftUI

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selectedItems: Set<PersistentIdentifier> = []
    @State private var showMoveSheet = false
    @State private var showCopySheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?

    var body: some View {
        Group {
            if deck.items.isEmpty {
                emptyState
            } else {
                cardListWithToolbar
            }
        }
        .navigationTitle(deck.name)
        .navigationDestination(for: RecognizedCard.self) { card in
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
        let sortedItems = deck.items.sorted { $0.addedAt > $1.addedAt }
        return VStack(spacing: 0) {
            List(selection: $selectedItems) {
                Section {
                    ForEach(sortedItems) { item in
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
                        Text("Cards")
                        Spacer()
                        Text("\(deck.items.count) card(s)")
                            .foregroundStyle(.secondary)
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
        selectedItems = Set(deck.items.map(\.persistentModelID))
    }

    func moveSelectedItems(to destination: MoveDestination) {
        let items = deck.items.filter { selectedItems.contains($0.persistentModelID) }
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
        let items = deck.items.filter { selectedItems.contains($0.persistentModelID) }
        switch destination {
        case .collection(let collection):
            for item in items {
                let copy = item.duplicate()
                copy.collection = collection
                modelContext.insert(copy)
            }
            collection.updatedAt = Date()
        case .deck(let targetDeck):
            for item in items {
                let copy = item.duplicate()
                copy.deck = targetDeck
                modelContext.insert(copy)
            }
            targetDeck.updatedAt = Date()
        }
        exitSelecting()
    }

    func deleteSelectedItems() {
        let items = deck.items.filter { selectedItems.contains($0.persistentModelID) }
        for item in items {
            modelContext.delete(item)
        }
        deck.updatedAt = Date()
        exitSelecting()
    }
}
