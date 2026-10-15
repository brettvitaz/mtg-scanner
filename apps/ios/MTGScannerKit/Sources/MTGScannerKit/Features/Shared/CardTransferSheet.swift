import SwiftData
import SwiftUI

struct CardTransferSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: CardTransferViewModel
    let onComplete: (CardTransferResult) -> Void

    init(items: [CollectionItem], operation: CardTransferOperation,
         onComplete: @escaping (CardTransferResult) -> Void) {
        _model = State(initialValue: CardTransferViewModel(items: items, operation: operation))
        self.onComplete = onComplete
    }

    init(model: CardTransferViewModel, onComplete: @escaping (CardTransferResult) -> Void) {
        _model = State(initialValue: model)
        self.onComplete = onComplete
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            taskList
                .navigationTitle("\(model.operation.rawValue) Cards")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { confirmation }
                .navigationDestination(for: CardTransferViewModel.Screen.self) { screen in
                    switch screen {
                    case .destinations: CardTransferDestinationPicker(model: model)
                    case .quantities: CardTransferQuantitiesView(model: model)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                }
        }
        .onChange(of: model.isDismissed) { _, dismissed in
            if dismissed { dismiss() }
        }
        .onDisappear { model.cancel() }
        .alert("Unable to \(model.operation.rawValue.lowercased()) cards", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Review Quantities") { model.reviewQuantities(in: modelContext) }
            Button("Cancel", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var taskList: some View {
        List {
            Section("Destination") {
                Button { model.showDestinations() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.destination?.name ?? "Choose Collection or Deck")
                                .fixedSize(horizontal: false, vertical: true)
                            if let destination = model.destination {
                                Text(destination.typeName).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Destination, \(destinationDescription)")
            }
            Section {
                Text(model.summary)
                Button("Review Quantities") { model.reviewQuantities(in: modelContext) }
                    .frame(minHeight: 44)
            } header: {
                Text("Cards")
            } footer: {
                Text(model.operation == .copy ? "Copy keeps the source unchanged."
                     : "Move removes the chosen quantities from the source.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var confirmation: some View {
        Button { model.submit(in: modelContext, onComplete: onComplete) } label: {
            Text(model.operation.rawValue)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSubmit)
        .padding()
        .background(.bar)
    }

    private var destinationDescription: String {
        guard let destination = model.destination else { return "Choose Collection or Deck" }
        return "\(destination.name), \(destination.typeName)"
    }
}

struct CardTransferDestinationPicker: View {
    @Bindable var model: CardTransferViewModel

    var body: some View {
        List {
            CardDestinationSections(filter: model.destinationFilter, onSelect: model.select)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Choose Destination")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CardTransferQuantitiesView: View {
    @Bindable var model: CardTransferViewModel

    var body: some View {
        List {
            Section {
                ForEach(model.rows) { row in
                    CardTransferQuantityRow(row: row, quantity: Binding(
                        get: { model.rows.first(where: { $0.id == row.id })?.quantity ?? row.quantity },
                        set: { model.setQuantity($0, for: row.id) }
                    ))
                }
            } footer: { Text(model.summary) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review Quantities")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CardTransferQuantityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: CardTransferRow
    @Binding var quantity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize { identity }
            Stepper(value: $quantity, in: 1...row.availableQuantity) {
                VStack(alignment: .leading, spacing: 4) {
                    if !dynamicTypeSize.isAccessibilitySize { identity }
                    Text("\(quantity) of \(row.availableQuantity)")
                        .font(.subheadline).monospacedDigit()
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel("\(row.title), \(row.printing)")
            .accessibilityValue("\(quantity) of \(row.availableQuantity)")
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

extension MoveDestination {
    var typeName: String {
        switch self {
        case .collection: "Collection"
        case .deck: "Deck"
        }
    }
}
