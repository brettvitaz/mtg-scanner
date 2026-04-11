import SwiftUI

/// Three-stage modal flow for manually adding a card to a collection or deck.
///
/// Stage 1 — Name Search: typeahead by card name
/// Stage 2 — Printing Selection: filterable list of printings for the chosen name
/// Stage 3 — Confirm & Add: image preview, quantity stepper, foil toggle, add button
struct AddCardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let onAdd: (CollectionItem) -> Void

    @State private var viewModel = AddCardViewModel()
    @State private var navigationPath: [AddCardRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            nameSearchView
                .navigationDestination(for: AddCardRoute.self) { route in
                    switch route {
                    case .printings:
                        printingSelectionView
                    case .confirm(let printing):
                        confirmView(printing: printing)
                    }
                }
        }
    }

    // MARK: - Stage 1: Name Search

    private var nameSearchView: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty && viewModel.searchText.count >= 2 {
                Text("No cards found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty {
                Text("Start typing a card name.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.searchResults, id: \.self) { name in
                    Button(name) {
                        viewModel.selectName(name, using: appModel)
                        navigationPath.append(.printings)
                    }
                    .foregroundStyle(.primary)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Add Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .searchable(text: Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0; viewModel.updateSearch(using: appModel) }
        ), prompt: "Card name")
    }

    // MARK: - Stage 2: Printing Selection

    private var printingSelectionView: some View {
        Group {
            if viewModel.isLoadingPrintings {
                ProgressView("Loading editions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredPrintings.isEmpty {
                Text(viewModel.printings.isEmpty ? "No printings found." : "No printings match the filter.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredPrintings) { printing in
                    Button {
                        navigationPath.append(.confirm(printing))
                    } label: {
                        PrintingRow(printing: printing)
                    }
                    .foregroundStyle(.primary)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(viewModel.selectedName ?? "Select Edition")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: Binding(
            get: { viewModel.printingFilterText },
            set: { viewModel.printingFilterText = $0 }
        ), prompt: "Filter by set, code, or number")
    }

    // MARK: - Stage 3: Confirm & Add

    @ViewBuilder
    private func confirmView(printing: CardPrinting) -> some View {
        @Bindable var vm = viewModel
        List {
            Section { cardImageRow(printing: printing) }
            cardIdentitySection(printing: printing)
            Section("Options") {
                Stepper("Quantity: \(viewModel.quantity)", value: $vm.quantity, in: 1...99)
                Toggle("Foil", isOn: $vm.isFoil)
            }
        }
        .navigationTitle("Add to Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let item = viewModel.buildCollectionItem(from: printing)
                    onAdd(item)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private func cardIdentitySection(printing: CardPrinting) -> some View {
        Section("Card") {
            LabeledContent("Name", value: printing.name)
            LabeledContent("Set", value: printing.setName ?? printing.setCode)
            if let cn = printing.collectorNumber {
                LabeledContent("Number", value: "#\(cn)")
            }
            if let rarity = printing.rarity {
                LabeledContent("Rarity") { RarityBadge(rarity: rarity) }
            }
        }
    }

    @ViewBuilder
    private func cardImageRow(printing: CardPrinting) -> some View {
        if let urlString = printing.imageUrl, let url = URL(string: urlString) {
            HStack {
                Spacer()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        cardImagePlaceholder
                    case .empty:
                        ProgressView()
                            .frame(height: 200)
                    @unknown default:
                        cardImagePlaceholder
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var cardImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 200)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}

// MARK: - Navigation Route

private enum AddCardRoute: Hashable {
    case printings
    case confirm(CardPrinting)
}
