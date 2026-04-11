import Foundation

@MainActor
@Observable
final class AddCardViewModel {
    // MARK: - Name search state

    var searchText: String = ""
    var searchResults: [String] = []
    var isSearching: Bool = false

    // MARK: - Printing selection state

    var selectedName: String?
    var printings: [CardPrinting] = []
    var printingFilterText: String = ""
    var isLoadingPrintings: Bool = false

    // MARK: - Card configuration

    var quantity: Int = 1
    var isFoil: Bool = false

    // MARK: - Error state

    var errorMessage: String?

    // MARK: - Private

    private var searchTask: Task<Void, Never>?

    // MARK: - Computed

    var filteredPrintings: [CardPrinting] {
        guard !printingFilterText.isEmpty else { return printings }
        let query = printingFilterText.lowercased()
        return printings.filter { printing in
            printing.setCode.lowercased().contains(query) ||
            (printing.setName ?? "").lowercased().contains(query) ||
            (printing.collectorNumber ?? "").lowercased().contains(query)
        }
    }

    // MARK: - Actions

    func updateSearch(using appModel: AppModel) {
        searchTask?.cancel()
        let query = searchText
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                searchResults = try await appModel.searchCardNames(query: query)
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    func selectName(_ name: String, using appModel: AppModel) {
        selectedName = name
        printings = []
        printingFilterText = ""
        isLoadingPrintings = true
        errorMessage = nil
        Task {
            do {
                printings = try await appModel.fetchPrintings(name: name)
            } catch {
                errorMessage = "Failed to load printings."
            }
            isLoadingPrintings = false
        }
    }

    func buildCollectionItem(from printing: CardPrinting) -> CollectionItem {
        CollectionItem(from: printing, foil: isFoil, quantity: quantity)
    }

    func reset() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        isSearching = false
        selectedName = nil
        printings = []
        printingFilterText = ""
        isLoadingPrintings = false
        quantity = 1
        isFoil = false
        errorMessage = nil
    }
}
