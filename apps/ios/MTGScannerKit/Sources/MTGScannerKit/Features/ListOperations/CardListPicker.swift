import SwiftData
import SwiftUI

enum CardListPickerRole: String, Hashable {
    case target = "Choose Target"
    case tool = "Choose Tool"
}

struct CardListPicker: View {
    @Query(sort: \CardCollection.updatedAt, order: .reverse) private var collections: [CardCollection]
    @Query(sort: \Deck.updatedAt, order: .reverse) private var decks: [Deck]
    @State private var search = ""
    let role: CardListPickerRole
    let excludedID: UUID?
    let onSelect: (CardListReference) -> Void

    private var lists: [CardListReference] {
        (collections.map(CardListReference.collection) + decks.map(CardListReference.deck)).filter {
            $0.id != excludedID && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Text(role == .target ? "This list receives the changes." : "This list supplies cards and quantities.")
                    .foregroundStyle(.secondary)
            }
            listSection("Collections", kind: .collection)
            listSection("Decks", kind: .deck)
        }
        .navigationTitle(role.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a collection or deck")
        .autocorrectionDisabled(true)
        .overlay {
            if lists.isEmpty {
                ContentUnavailableView(
                    "No Lists Available", systemImage: "rectangle.stack",
                    description: Text("Choose another target, create a list in Library, or change your search.")
                )
            }
        }
    }

    private func listSection(_ title: String, kind: CardListKind) -> some View {
        Section(title) {
            ForEach(lists.filter { $0.kind == kind }, id: \.id) { list in
                Button { onSelect(list) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.name).foregroundStyle(.primary)
                        Text("\(list.kind.rawValue) · \(list.quantitySummary)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("\(list.name), \(list.kind.rawValue), \(list.quantitySummary)")
            }
        }
    }
}
