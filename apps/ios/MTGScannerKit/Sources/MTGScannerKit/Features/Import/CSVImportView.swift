import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    let destination: CSVImportDestination
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CSVImportViewModel()
    @State private var showFilePicker = false
    @State private var selectedRow: CSVImportRow?
    @State private var importTask: Task<Void, Never>?
    @State private var importedQuantity: Int?

    init(destination: CSVImportDestination, viewModel: CSVImportViewModel = CSVImportViewModel()) {
        self.destination = destination
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                fileSection
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.primary) }
                if !viewModel.rows.isEmpty { reviewSection }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { save() }.disabled(!viewModel.canImport)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let error): viewModel.errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $selectedRow) { row in
                if let record = row.record {
                    CSVPrintingPicker(record: record) { viewModel.choose($0, for: row.id) }
                }
            }
            .alert("Import Complete", isPresented: Binding(
                get: { importedQuantity != nil }, set: { if !$0 { dismiss() } }
            )) {
                Button("Done") { dismiss() }
            } message: {
                Text("Added \(importedQuantity ?? 0) cards to \(destination.name).")
            }
            .onDisappear { importTask?.cancel() }
        }
    }

    private var fileSection: some View {
        Section {
            LabeledContent("Destination") { Text(destination.name).foregroundStyle(.primary) }
            Text("Choose a CSV exported by this app. Matching cards gain quantity; existing cards are kept.")
                .foregroundStyle(.primary)
            Button(viewModel.filename.isEmpty ? "Choose CSV File" : "Choose Another File") { showFilePicker = true }
                .disabled(viewModel.isLoading)
            if !viewModel.filename.isEmpty { Text(viewModel.filename).font(.subheadline) }
            if viewModel.isLoading {
                ProgressView("Resolving cards: \(viewModel.processedRows) of \(viewModel.rows.count)")
            }
        }
    }

    private var reviewSection: some View {
        Section("Review Cards") {
            if let quantity = viewModel.totalQuantity {
                Text("\(quantity) cards • \(viewModel.skippedCount) rows skipped")
            } else {
                Text("Quantity is too large. Reduce quantities in the file or skip rows.")
            }
            Text("Resolve or skip every row before importing. Re-importing this file adds its quantities again.")
                .font(.subheadline).foregroundStyle(.primary)
            Button("Retry Unresolved Rows") {
                importTask = Task { await viewModel.resolve(fetch: appModel.fetchPrintings) }
            }
            .disabled(viewModel.isLoading)
            ForEach(viewModel.rows) { row in reviewRow(row) }
        }
    }

    private func reviewRow(_ row: CSVImportRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Row \(row.id): \(row.title.isEmpty ? "Missing title" : row.title)").font(.headline)
            if let record = row.record {
                Text("\(record.quantity) × \(record.edition) · \(record.foil ? "Foil" : "Nonfoil")")
                    .font(.subheadline)
            }
            if row.isSkipped {
                Label("Skipped", systemImage: "minus.circle")
            } else if let printing = row.printing {
                Label("Resolved: \(printing.name)", systemImage: "checkmark.circle")
                Text("\(printing.setName ?? printing.setCode) · #\(printing.collectorNumber ?? "—")")
                    .font(.subheadline)
            } else if let issue = row.issue {
                Label(issue, systemImage: "exclamationmark.circle").font(.subheadline)
            }
            HStack {
                if row.record != nil {
                    Button("Choose Printing") { selectedRow = row }.frame(minHeight: 44)
                }
                Spacer()
                Button(row.isSkipped ? "Include Row" : "Skip Row") { viewModel.toggleSkip(row.id) }
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
        }
        .padding(.vertical, 4)
    }

    private func load(_ url: URL) {
        importTask?.cancel()
        importTask = Task { await viewModel.load(url: url, fetch: appModel.fetchPrintings) }
    }

    private func save() {
        do {
            importedQuantity = try CSVImportPersistence().save(
                rows: viewModel.rows, to: destination, context: modelContext, commit: modelContext.save
            )
        } catch {
            viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
