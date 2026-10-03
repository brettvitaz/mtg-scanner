import SwiftData
import SwiftUI

struct CopyMoveSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [CardTransferRow]
    @State private var operation = CardTransferOperation.copy
    @State private var errorMessage: String?

    let onComplete: (CardTransferResult) -> Void

    init(items: [CollectionItem], onComplete: @escaping (CardTransferResult) -> Void) {
        _rows = State(initialValue: items.map { CardTransferRow(item: $0) })
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Operation", selection: $operation) {
                        ForEach(CardTransferOperation.allCases) { operation in
                            Text(operation.rawValue).tag(operation)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                quantitiesSection
                CardDestinationSections(
                    excludedCollections: Set(rows.compactMap(\.collectionID)),
                    excludedDecks: Set(rows.compactMap(\.deckID)),
                    onSelect: transfer
                )
            }
            .navigationTitle("Copy/Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Unable to \(operation.rawValue.lowercased()) cards", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Review Quantities") { refreshRows() }
                Button("Cancel", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var quantitiesSection: some View {
        Section("Quantities") {
            ForEach($rows) { $row in
                CardTransferQuantityRow(row: $row)
            }
        }
    }

    private func transfer(to destination: MoveDestination) {
        do {
            let result = try CardTransfer.perform(rows: rows, operation: operation,
                                                  destination: destination, context: modelContext)
            onComplete(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshRows() {
        do {
            let items = try modelContext.fetch(FetchDescriptor<CollectionItem>())
            rows = rows.compactMap { row in
                guard let item = items.first(where: { $0.id == row.id && !$0.isDeleted }) else { return nil }
                var refreshed = CardTransferRow(item: item)
                refreshed.quantity = min(row.quantity, refreshed.availableQuantity)
                return refreshed
            }
            if rows.isEmpty { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CardTransferQuantityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var row: CardTransferRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize { identity }
            Stepper(value: $row.quantity, in: 1...row.availableQuantity) {
                VStack(alignment: .leading, spacing: 4) {
                    if !dynamicTypeSize.isAccessibilitySize { identity }
                    Text("\(row.quantity) of \(row.availableQuantity)")
                        .font(.subheadline).monospacedDigit()
                }
            }
            .accessibilityLabel("\(row.title), \(row.printing)")
            .accessibilityValue("\(row.quantity) of \(row.availableQuantity)")
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title).font(.body)
            Text(row.printing).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
