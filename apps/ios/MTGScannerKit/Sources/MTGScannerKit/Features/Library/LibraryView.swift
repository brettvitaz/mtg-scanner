import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Query(sort: \CardCollection.updatedAt, order: .reverse) private var collections: [CardCollection]
    @Query(sort: \Deck.updatedAt, order: .reverse) private var decks: [Deck]

    @State private var showNewCollection = false
    @State private var showNewDeck = false
    @State private var newName = ""

    @State private var showRenameCollection = false
    @State private var showRenameDeck = false
    @State private var renamingCollection: CardCollection?
    @State private var renamingDeck: Deck?
    @State private var editingName = ""

    @State private var showSearch = false
    @State private var searchText = ""

    private var filteredCollections: [CardCollection] {
        guard !searchText.isEmpty else { return collections }
        return collections.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredDecks: [Deck] {
        guard !searchText.isEmpty else { return decks }
        return decks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            libraryList
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            if showSearch {
                ListSearchField(text: $searchText, prompt: "Search collections and decks")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            List {
                collectionsSection
                decksSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.dsBackground)
        }
        .background(Color.dsBackground)
        .navigationTitle("Library")
        .toolbar { libraryToolbar }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Name", text: $newName)
            Button("Create") { createCollection() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Deck", isPresented: $showNewDeck) {
            TextField("Name", text: $newName)
            Button("Create") { createDeck() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: $showRenameCollection) {
            TextField("Name", text: $editingName)
            Button("Save") { renameCollection() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Deck", isPresented: $showRenameDeck) {
            TextField("Name", text: $editingName)
            Button("Save") { renameDeck() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(for: CardCollection.self) { collection in
            CollectionDetailView(collection: collection)
        }
        .navigationDestination(for: Deck.self) { deck in
            DeckDetailView(deck: deck)
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                }
            } label: {
                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
            }
            .accessibilityLabel(showSearch ? "Close search" : "Search")
            Menu {
                Button("New Collection") {
                    newName = ""
                    showNewCollection = true
                }
                Button("New Deck") {
                    newName = ""
                    showNewDeck = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add library item")
        }
    }

    // MARK: - Sections

    private var collectionsSection: some View {
        Section(header: sectionHeader("COLLECTIONS", count: filteredCollections.count)) {
            if collections.isEmpty {
                emptyRow("No collections yet")
            } else {
                ForEach(filteredCollections) { collection in
                    collectionRow(for: collection)
                }
                .onDelete { offsets in
                    for index in offsets {
                        libraryViewModel.deleteCollection(filteredCollections[index])
                    }
                }
                if filteredCollections.isEmpty {
                    emptyRow("No results for \"\(searchText)\"")
                }
            }
        }
    }

    private var decksSection: some View {
        Section(header: sectionHeader("DECKS", count: filteredDecks.count)) {
            if decks.isEmpty {
                emptyRow("No decks yet")
            } else {
                ForEach(filteredDecks) { deck in
                    deckRow(for: deck)
                }
                .onDelete { offsets in
                    for index in offsets {
                        libraryViewModel.deleteDeck(filteredDecks[index])
                    }
                }
                if filteredDecks.isEmpty {
                    emptyRow("No results for \"\(searchText)\"")
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.geist(.caption))
                .foregroundStyle(Color.dsTextSecondary)
                .textCase(nil)
            Spacer()
            Text("\(count)")
                .font(.geist(.caption))
                .foregroundStyle(Color.dsTextSecondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.geist(.body))
            .foregroundStyle(Color.dsTextSecondary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

}

// MARK: - Row builders + Actions

private extension LibraryView {
    func collectionRow(for collection: CardCollection) -> some View {
        NavigationLink(value: collection) {
            LibraryItemRow(
                iconSystemName: "folder.fill",
                name: collection.name,
                cardCount: collection.items.totalQuantity,
                updatedAt: collection.updatedAt
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            Button {
                renamingCollection = collection
                editingName = collection.name
                showRenameCollection = true
            } label: { Label("Rename", systemImage: "pencil") }
        }
    }

    func deckRow(for deck: Deck) -> some View {
        NavigationLink(value: deck) {
            LibraryItemRow(
                iconSystemName: "rectangle.stack.fill",
                name: deck.name,
                cardCount: deck.items.totalQuantity,
                updatedAt: deck.updatedAt
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            Button {
                renamingDeck = deck
                editingName = deck.name
                showRenameDeck = true
            } label: { Label("Rename", systemImage: "pencil") }
        }
    }

    func createCollection() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        libraryViewModel.createCollection(name: trimmed)
    }

    func createDeck() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        libraryViewModel.createDeck(name: trimmed)
    }

    func renameCollection() {
        guard let collection = renamingCollection else { return }
        libraryViewModel.renameCollection(collection, to: editingName)
        renamingCollection = nil
    }

    func renameDeck() {
        guard let deck = renamingDeck else { return }
        libraryViewModel.renameDeck(deck, to: editingName)
        renamingDeck = nil
    }
}
