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

    var body: some View {
        NavigationStack {
            libraryList
        }
    }

    private var libraryList: some View {
        List {
            collectionsSection
            decksSection
        }
        .navigationTitle("Library")
        .toolbar { addMenu }
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

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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
        Section("Collections") {
            if collections.isEmpty {
                Text("No collections yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    CollectionRow(name: collection.name, count: collection.items.totalQuantity)
                }
                .contextMenu {
                    Button {
                        renamingCollection = collection
                        editingName = collection.name
                        showRenameCollection = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    libraryViewModel.deleteCollection(collections[index])
                }
            }
        }
    }

    private var decksSection: some View {
        Section("Decks") {
            if decks.isEmpty {
                Text("No decks yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(decks) { deck in
                NavigationLink(value: deck) {
                    CollectionRow(name: deck.name, count: deck.items.totalQuantity)
                }
                .contextMenu {
                    Button {
                        renamingDeck = deck
                        editingName = deck.name
                        showRenameDeck = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    libraryViewModel.deleteDeck(decks[index])
                }
            }
        }
    }

    // MARK: - Actions

    private func createCollection() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        libraryViewModel.createCollection(name: trimmed)
    }

    private func createDeck() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        libraryViewModel.createDeck(name: trimmed)
    }

    private func renameCollection() {
        guard let collection = renamingCollection else { return }
        libraryViewModel.renameCollection(collection, to: editingName)
        renamingCollection = nil
    }

    private func renameDeck() {
        guard let deck = renamingDeck else { return }
        libraryViewModel.renameDeck(deck, to: editingName)
        renamingDeck = nil
    }
}

// MARK: - Row

private struct CollectionRow: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text("\(count) card(s)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) card(s)")
    }
}
