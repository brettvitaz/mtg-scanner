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
    var searchError: String?
    private(set) var printingTask: Task<Void, Never>?

    // MARK: - Private

    var searchTask: Task<Void, Never>?
    var lastSearchedQuery: String = ""

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

    func updateSearch(using catalog: any CardCatalog) {
        searchTask?.cancel()
        searchError = nil
        isSearching = false
        let query = searchText
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        if query == lastSearchedQuery && !searchResults.isEmpty { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, query == searchText else { return }
            await search(query, using: catalog)
        }
    }

    private func search(_ query: String, using catalog: any CardCatalog) async {
        isSearching = true
        do {
            let results = try await catalog.searchCardNames(query: query)
            guard !Task.isCancelled, query == searchText else { return }
            searchResults = results
            lastSearchedQuery = query
        } catch {
            guard !Task.isCancelled, query == searchText else { return }
            searchResults = []
            searchError = "Could not search cards."
        }
        isSearching = false
    }

    func selectName(_ name: String, using catalog: any CardCatalog) {
        printingTask?.cancel()
        selectedName = name
        printings = []
        printingFilterText = ""
        isLoadingPrintings = true
        errorMessage = nil
        printingTask = Task {
            do {
                let results = try await catalog.fetchPrintings(name: name)
                guard !Task.isCancelled, selectedName == name else { return }
                printings = results
            } catch {
                guard !Task.isCancelled, selectedName == name else { return }
                errorMessage = "Failed to load printings."
            }
            isLoadingPrintings = false
        }
    }

    func buildCollectionItem(from printing: CardPrinting) -> CollectionItem {
        CollectionItem(from: printing, foil: isFoil, quantity: quantity)
    }

}
