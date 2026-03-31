import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    @Bindable var collection: CardCollection
    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selectedItems: Set<PersistentIdentifier> = []
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?

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
        let sortedItems = collection.items.sorted { $0.addedAt > $1.addedAt }
        return VStack(spacing: 0) {
            List(selection: isSelecting ? $selectedItems : nil) {
                Section {
                    ForEach(sortedItems) { item in
                        NavigationLink(value: item.toRecognizedCard()) {
                            CollectionItemRow(item: item)
                        }
                    }
                } header: {
                    HStack {
                        Text("Cards")
                        Spacer()
                        Text("\(collection.items.count) card(s)")
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
        selectedItems = Set(collection.items.map(\.persistentModelID))
    }

    private func copySelectedItems(to destination: MoveDestination) {
        let items = collection.items.filter { selectedItems.contains($0.persistentModelID) }
        switch destination {
        case .collection(let targetCollection):
            for item in items {
                let copy = item.duplicate()
                copy.collection = targetCollection
                modelContext.insert(copy)
            }
            targetCollection.updatedAt = Date()
        case .deck(let deck):
            for item in items {
                let copy = item.duplicate()
                copy.deck = deck
                modelContext.insert(copy)
            }
            deck.updatedAt = Date()
        }
        exitSelecting()
    }

    private func deleteSelectedItems() {
        let items = collection.items.filter { selectedItems.contains($0.persistentModelID) }
        for item in items {
            modelContext.delete(item)
        }
        collection.updatedAt = Date()
        exitSelecting()
    }
}
