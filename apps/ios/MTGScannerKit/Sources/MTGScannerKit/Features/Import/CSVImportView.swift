import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    let destination: CardListReference
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel = CSVImportViewModel()
    @State private var showFilePicker = false
    @State private var importTask: Task<Void, Never>?
    @State private var operationViewModel: CardListOperationViewModel?
    @State private var showReview = false

    init(
        destination: CardListReference, viewModel: CSVImportViewModel = CSVImportViewModel()
    ) {
        self.destination = destination
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            reviewList
                .navigationTitle("Import CSV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .navigationDestination(isPresented: $showReview) {
                    if let operationViewModel {
                        CSVOperationReviewScreen(viewModel: operationViewModel) { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !viewModel.rows.isEmpty && !dynamicTypeSize.isAccessibilitySize { importBar }
                }
        }
        .tint(Color.dsAccent)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private var reviewList: some View {
        List {
            headerSection
            if let error = viewModel.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle") }
                    .listRowBackground(Color.dsBackground)
            }
            if !viewModel.rows.isEmpty && !viewModel.isLoading {
                attentionSection
                groupedRowsSection
                importNotesSection
            }
        }
        .modifier(CSVImportListStyle())
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(statusTitle).font(CSVImportStyle.heading).foregroundStyle(Color.dsTextPrimary)
                if let subtitle = statusSubtitle {
                    Text(subtitle).font(CSVImportStyle.metadata).foregroundStyle(CSVImportStyle.secondaryText)
                }
                if viewModel.isLoading {
                    ProgressView("Checked \(viewModel.processedRows) of \(viewModel.rows.count) rows")
                        .font(CSVImportStyle.metadata)
                }
                fileContext
            }
            .padding(.vertical, Spacing.xs)
        }
        .listRowBackground(Color.dsBackground)
        .listRowSeparator(.hidden)
    }

    private var statusTitle: String {
        if viewModel.isLoading { return "Matching cards…" }
        if viewModel.rows.isEmpty { return "Import CSV into \(destination.name)" }
        if viewModel.totalQuantity == nil { return "Reduce import quantity" }
        let count = viewModel.attentionRows.count
        if count > 0 { return "\(count) \(count == 1 ? "row needs" : "rows need") attention" }
        guard let quantity = viewModel.readyQuantity, quantity > 0 else { return "No cards selected" }
        return "\(quantity) \(quantity == 1 ? "card" : "cards") matched"
    }

    private var statusSubtitle: String? {
        if viewModel.isLoading { return nil }
        if viewModel.rows.isEmpty { return "Choose a CSV exported by this app." }
        if viewModel.totalQuantity == nil { return "Lower quantities in the CSV or skip rows." }
        if !viewModel.attentionRows.isEmpty, let quantity = viewModel.readyQuantity {
            return "\(quantity) \(quantity == 1 ? "card is" : "cards are") matched."
        }
        if viewModel.readyRows.isEmpty { return "Include a row from Skipped to review." }
        return nil
    }

    @ViewBuilder
    private var fileContext: some View {
        if viewModel.filename.isEmpty {
            Button("Choose CSV File") { showFilePicker = true }
                .foregroundStyle(Color.dsAccent).frame(minHeight: 44)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.lg) { fileLabel; Spacer(minLength: 0); changeFileButton }
                VStack(alignment: .leading, spacing: Spacing.xs) { fileLabel; changeFileButton }
            }
        }
    }

    private var fileLabel: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Target: \(destination.name)")
            Text(viewModel.filename)
        }
        .font(CSVImportStyle.metadata)
        .foregroundStyle(CSVImportStyle.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var changeFileButton: some View {
        Button("Change File") { showFilePicker = true }
            .foregroundStyle(Color.dsAccent)
            .font(CSVImportStyle.metadata)
            .frame(minHeight: 44)
            .disabled(viewModel.isLoading)
    }

    private var undoButton: some View {
        Button("Undo") { viewModel.undoSkipAllUnmatched() }
            .frame(minHeight: 44)
            .disabled(!viewModel.canUndoSkipAll)
            .accessibilityLabel("Undo Skip All Unmatched")
    }

    @ViewBuilder
    private var attentionSection: some View {
        if !viewModel.attentionRows.isEmpty {
            Section {
                ForEach(viewModel.attentionRows) { row in CSVImportRowLink(row: row, viewModel: viewModel) }
            } header: {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Review"); Spacer(); skipAllButton }
                    VStack(alignment: .leading, spacing: Spacing.xs) { Text("Review"); skipAllButton }
                }
                .font(CSVImportStyle.metadata)
                .textCase(nil)
            } footer: {
                Text("Review or skip each row to continue.")
                    .font(CSVImportStyle.metadata).foregroundStyle(CSVImportStyle.secondaryText)
            }
            .listRowBackground(Color.dsBackground)
        }
    }

    private var skipAllButton: some View {
        Button("Skip All Unmatched (\(viewModel.attentionRows.count))") { viewModel.skipAllUnmatched() }
            .frame(minHeight: 44)
            .disabled(viewModel.isLoading)
    }

    private var groupedRowsSection: some View {
        Section {
            if !viewModel.readyRows.isEmpty {
                NavigationLink {
                    CSVImportReviewedList(viewModel: viewModel, showSkipped: false)
                } label: {
                    reviewGroupLabel(
                        "Included Cards", count: viewModel.readyRows.count, quantity: viewModel.readyQuantity
                    )
                }
            }
            if viewModel.skippedCount > 0 { skippedRow }
        }
        .listRowBackground(Color.dsBackground)
    }

    private var skippedRow: some View {
        HStack(spacing: Spacing.lg) {
            NavigationLink {
                CSVImportReviewedList(viewModel: viewModel, showSkipped: true)
            } label: {
                reviewGroupLabel("Skipped", count: viewModel.skippedCount, quantity: nil)
            }
            if viewModel.bulkSkippedCount > 0 { undoButton.buttonStyle(.borderless) }
        }
    }

    private func reviewGroupLabel(_ title: String, count: Int, quantity: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(CSVImportStyle.cardName).foregroundStyle(Color.dsAccent)
            Text([rowCount(count), quantity.map { "\($0) cards" }].compactMap { $0 }.joined(separator: " · "))
                .font(CSVImportStyle.metadata).foregroundStyle(CSVImportStyle.secondaryText)
        }
    }

    private var importNotesSection: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize { importButton }
        } footer: {
            Text("Next: choose Add or Subtract and review quantity changes.")
                .font(CSVImportStyle.metadata).foregroundStyle(CSVImportStyle.secondaryText)
        }
        .listRowBackground(Color.dsBackground)
        .listRowSeparator(.hidden)
    }

    private var importBar: some View {
        importButton
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: CSVImportStyle.contentWidth)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }

    private var importButton: some View {
        Button(action: prepareReview) {
            Text("Review Changes")
                .font(CSVImportStyle.body)
                .foregroundStyle(importButtonTextColor)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.dsAccent)
        .disabled(!viewModel.canImport)
    }

    private var importButtonTextColor: Color {
        if !viewModel.canImport { return CSVImportStyle.secondaryText }
        return colorScheme == .dark ? Color.dsBackground : .white
    }

    private func rowCount(_ count: Int) -> String { "\(count) \(count == 1 ? "row" : "rows")" }

    private func load(_ url: URL) {
        importTask?.cancel()
        importTask = Task { await viewModel.load(url: url, fetch: appModel.fetchPrintings) }
    }

    private func prepareReview() {
        guard viewModel.canImport else { return }
        do {
            operationViewModel = CardListOperationViewModel(
                target: destination, csvItems: try CSVImportPersistence().preparedItems(viewModel.rows),
                csvName: viewModel.filename.isEmpty ? "CSV" : viewModel.filename, operation: .add
            )
            showReview = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
