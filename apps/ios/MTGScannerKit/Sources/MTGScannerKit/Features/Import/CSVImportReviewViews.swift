import SwiftUI

struct CSVImportRowLink: View {
    let row: CSVImportRow
    let viewModel: CSVImportViewModel

    var body: some View {
        NavigationLink {
            CSVImportRowDetail(rowID: row.id, viewModel: viewModel)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.printing?.name ?? (row.title.isEmpty ? "Missing title" : row.title))
                        .font(CSVImportStyle.cardName)
                    Spacer()
                    if let record = row.record {
                        Text("×\(record.quantity)").font(CSVImportStyle.quantity).monospacedDigit()
                    }
                }
                if let record = row.record {
                    Text(printingSummary(record)).font(CSVImportStyle.metadata)
                        .foregroundStyle(CSVImportStyle.secondaryText)
                }
                if !row.isSkipped, row.printing == nil, let issue = row.issue {
                    Label(issue.components(separatedBy: ". ").first ?? issue,
                          systemImage: "exclamationmark.circle")
                        .font(CSVImportStyle.metadata).foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(viewModel.isLoading)
    }

    private func printingSummary(_ record: CSVImportRecord) -> String {
        let edition = row.printing?.setName ?? row.printing?.setCode ?? record.edition
        let number = row.printing?.collectorNumber ?? record.collectorNumber
        return [edition, number.map { "#\($0)" }, record.foil ? "Foil" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct CSVImportReviewedList: View {
    let viewModel: CSVImportViewModel
    let showSkipped: Bool
    private var rows: [CSVImportRow] { showSkipped ? viewModel.skippedRows : viewModel.readyRows }

    var body: some View {
        List {
            if rows.isEmpty {
                Text(showSkipped ? "No skipped rows." : "No ready cards.").foregroundStyle(.primary)
            }
            ForEach(rows) { row in
                CSVImportRowLink(row: row, viewModel: viewModel).listRowBackground(Color.dsSurface)
            }
        }
        .modifier(CSVImportListStyle())
        .navigationTitle(showSkipped ? "Skipped" : "Included Cards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CSVImportRowDetail: View {
    let rowID: Int
    let viewModel: CSVImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPrintingPicker = false
    @State private var didChoosePrinting = false
    private var row: CSVImportRow? { viewModel.rows.first { $0.id == rowID } }

    var body: some View {
        List {
            if let row {
                sourceSection(row)
                matchSection(row)
                actionsSection(row)
            }
        }
        .modifier(CSVImportListStyle())
        .navigationTitle(row?.title.nonEmpty ?? "Review Row")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPrintingPicker, onDismiss: finishChoosing) {
            if let record = row?.record {
                CSVPrintingPicker(record: record) { printing in
                    viewModel.choose(printing, for: rowID)
                    didChoosePrinting = true
                }
            }
        }
    }

    private func sourceSection(_ row: CSVImportRow) -> some View {
        Section("CSV Row \(rowID)") {
            Text(row.title.isEmpty ? "Missing title" : row.title).font(CSVImportStyle.cardName)
            if let record = row.record {
                CSVImportField(title: "Quantity", value: "\(record.quantity)")
                CSVImportField(title: "Edition", value: record.edition)
                CSVImportField(title: "Finish", value: record.foil ? "Foil" : "Nonfoil")
                identifierDetails(record)
            }
        }
        .listRowBackground(Color.dsSurface)
    }

    @ViewBuilder
    private func identifierDetails(_ record: CSVImportRecord) -> some View {
        if record.setCode != nil || record.collectorNumber != nil || record.scryfallId != nil {
            DisclosureGroup("CSV Identifiers") {
                if let code = record.setCode { CSVImportField(title: "Set code", value: code) }
                if let number = record.collectorNumber { CSVImportField(title: "Collector number", value: number) }
                if let identifier = record.scryfallId { CSVImportField(title: "Scryfall ID", value: identifier) }
            }
        }
    }

    @ViewBuilder
    private func matchSection(_ row: CSVImportRow) -> some View {
        if let printing = row.printing {
            Section("Matched Printing") {
                Text(printing.name).font(CSVImportStyle.cardName)
                CSVImportField(title: "Set", value: printing.setName ?? printing.setCode)
                if let number = printing.collectorNumber { CSVImportField(title: "Collector number", value: number) }
            }
            .listRowBackground(Color.dsSurface)
        } else if let issue = row.issue {
            Section("Needs Attention") {
                Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(Color.dsTextPrimary)
            }
            .listRowBackground(Color.dsSurface)
        }
    }

    private func actionsSection(_ row: CSVImportRow) -> some View {
        Section {
            if row.isSkipped { Label("This row is skipped", systemImage: "minus.circle") }
            if row.record != nil {
                Button(row.printing == nil ? "Choose Printing" : "Change Printing") {
                    showPrintingPicker = true
                }
            }
            Button(row.isSkipped ? "Include Row" : "Skip Row") {
                viewModel.toggleSkip(rowID)
                dismiss()
            }
        }
        .disabled(viewModel.isLoading)
        .listRowBackground(Color.dsSurface)
    }

    private func finishChoosing() {
        guard didChoosePrinting else { return }
        dismiss()
    }
}

private struct CSVImportField: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(CSVImportStyle.secondaryText)
        }
    }
}
