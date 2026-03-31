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
    @State private var selectedItems: Set<PersistentIdentifier> = []
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var exportFile: ExportActivityItem?

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
            .navigationDestination(for: RecognizedCard.self) { card in
                CardDetailView(card: card)
                    .environmentObject(appModel)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToSheet(title: "Move To") { destination in
                moveSelectedItems(to: destination)
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
                    ForEach(inboxItems) { item in
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
                        Text("\(inboxItems.count) card(s)")
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
                    Image(systemName: "folder")
                    Text("Move").font(.caption2)
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
        selectedItems = Set(inboxItems.map(\.persistentModelID))
    }

    private func moveSelectedItems(to destination: MoveDestination) {
        let items = inboxItems.filter { selectedItems.contains($0.persistentModelID) }
        switch destination {
        case .collection(let collection):
            for item in items {
                item.collection = collection
                item.deck = nil
            }
            collection.updatedAt = Date()
        case .deck(let deck):
            for item in items {
                item.deck = deck
                item.collection = nil
            }
            deck.updatedAt = Date()
        }
        exitSelecting()
    }

    private func deleteSelectedItems() {
        let items = inboxItems.filter { selectedItems.contains($0.persistentModelID) }
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
