import SwiftUI

struct CSVPrintingPicker: View {
    let record: CSVImportRecord
    let onChoose: (CardPrinting) -> Void
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddCardViewModel()
    @State private var retryCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the exact printing for \(record.quantity) \(record.foil ? "foil" : "nonfoil") copies.")
                        .foregroundStyle(.primary)
                    TextField("Search card name", text: $viewModel.searchText)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.searchText) { _, _ in viewModel.updateSearch(using: appModel) }
                    ForEach(viewModel.searchResults, id: \.self) { name in
                        Button(name) { viewModel.selectedName = name }
                    }
                }
                if viewModel.isLoadingPrintings || viewModel.isSearching {
                    ProgressView("Loading cards…")
                }
                printingSection
            }
            .navigationTitle("Choose Printing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { viewModel.selectedName = record.title }
            .task(id: "\(viewModel.selectedName ?? record.title)-\(retryCount)") { await loadPrintings() }
            .onDisappear { viewModel.searchTask?.cancel() }
        }
    }

    private func loadPrintings() async {
        viewModel.isLoadingPrintings = true
        viewModel.errorMessage = nil
        viewModel.printings = []
        do {
            let printings = try await appModel.fetchPrintings(name: viewModel.selectedName ?? record.title)
            try Task.checkCancellation()
            viewModel.printings = printings
        } catch {
            guard !Task.isCancelled else { return }
            viewModel.errorMessage = "Failed to load printings. Retry or search for another name."
        }
        guard !Task.isCancelled else { return }
        viewModel.isLoadingPrintings = false
    }

    private var printingSection: some View {
        Section(viewModel.selectedName ?? record.title) {
            TextField("Filter by set or collector number", text: $viewModel.printingFilterText)
                .autocorrectionDisabled(true)
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.primary)
                Button("Retry") {
                    retryCount += 1
                }
            } else if !viewModel.isLoadingPrintings && viewModel.filteredPrintings.isEmpty {
                Text("No printings found. Search for another card name.").foregroundStyle(.primary)
            }
            ForEach(viewModel.filteredPrintings) { printing in
                Button {
                    onChoose(printing)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        PrintingRow(printing: printing)
                        if !CSVPrintingResolver().supportsFinish(record, printing: printing) {
                            Text("Unavailable in the requested finish").font(.caption)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(!CSVPrintingResolver().supportsFinish(record, printing: printing))
            }
        }
    }
}
