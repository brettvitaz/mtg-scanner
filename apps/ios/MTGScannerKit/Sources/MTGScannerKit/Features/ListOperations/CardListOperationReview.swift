import SwiftData
import SwiftUI

struct CardListOperationReview: View {
    @Bindable var viewModel: CardListOperationViewModel

    var body: some View {
        if let receipt = viewModel.receipt {
            completion(receipt.plan)
        } else {
            choices
            if let plan = viewModel.plan { preview(plan) }
        }
        if let error = viewModel.errorMessage {
            Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.primary) }
        }
    }

    private var choices: some View {
        Section("Operation") {
            Picker("Operation", selection: $viewModel.operation) {
                ForEach(CardListOperation.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            if !viewModel.isCSV {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tool list afterward").font(.subheadline)
                    Picker("Tool list afterward", selection: $viewModel.deleteTool) {
                        Text("Keep").tag(false)
                        Text("Delete").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                }
            }
        }
        .onChange(of: viewModel.operation) { viewModel.refresh() }
        .onChange(of: viewModel.deleteTool) { viewModel.refresh() }
    }

    @ViewBuilder
    private func preview(_ plan: CardListOperationPlan) -> some View {
        Section("What Will Happen") {
            Text("\(plan.operation.rawValue) \(plan.toolName) \(plan.operation == .add ? "into" : "from") "
                 + plan.target.name).font(.headline)
            Text(plan.outcome)
            LabeledContent("\(plan.target.name) total") {
                Text("\(plan.beforeQuantity) → \(plan.afterQuantity)").monospacedDigit()
            }
            if plan.unavailableQuantity > 0 {
                Label(
                    "\(plan.unavailableQuantity) requested copies unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
            if !plan.canApply {
                Text("No quantities would change. Choose another tool or operation.")
                    .foregroundStyle(.secondary)
            }
        }
        if plan.unavailableQuantity > 0 {
            Section {
                DisclosureGroup("Unavailable Copies (\(plan.unavailableQuantity))") {
                    Text("Only available copies of the exact printing and finish will be removed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(plan.changes.filter { $0.unavailable > 0 }) { changeRow($0) }
                }
            }
        }
        Section {
            DisclosureGroup("Card Changes (\(plan.changes.count))") {
                ForEach(plan.changes) { changeRow($0) }
            }
        } footer: {
            Text("Repeating this action applies its quantities again.")
        }
    }

    private func changeRow(_ change: CardListQuantityChange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.item.card.title ?? "Unknown").font(.headline)
            Text("\(change.item.card.edition ?? "Unknown") · #\(change.item.card.collectorNumber ?? "—") · "
                 + (change.item.card.foil == true ? "Foil" : "Nonfoil"))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("\(change.before) → \(change.after) copies")
            if change.unavailable > 0 {
                Text("Requested \(change.requested); \(change.unavailable) unavailable")
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func completion(_ plan: CardListOperationPlan) -> some View {
        Section {
            Label(viewModel.wasUndone ? "Operation Undone" : "Changes Saved", systemImage: "checkmark.circle")
                .font(.headline)
            Text(viewModel.wasUndone ? "The original lists and quantities have been restored."
                 : "\(plan.operation.pastTense) \(plan.affectedQuantity) cards "
                 + "\(plan.operation == .add ? "to" : "from") \(plan.target.name).")
            if !viewModel.wasUndone, plan.deleteTool {
                Text("Deleted \(plan.toolName). Undo will restore it.")
            }
            if !viewModel.wasUndone, plan.unavailableQuantity > 0 {
                Text("\(plan.unavailableQuantity) requested copies were unavailable.")
            }
        } footer: {
            Text("Undo is available until you leave this screen.")
        }
    }
}

struct CardListOperationFooter: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: CardListOperationViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.receipt != nil {
                if !viewModel.wasUndone {
                    Button("Undo") { viewModel.undo(context: modelContext, commit: modelContext.save) }
                        .buttonStyle(.bordered).disabled(viewModel.isApplying)
                }
                Button("Done", action: onDone).buttonStyle(.borderedProminent)
            } else {
                if let plan = viewModel.plan, plan.unavailableQuantity > 0 {
                    Label(
                        "\(plan.unavailableQuantity) requested copies unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.subheadline)
                }
                Button(viewModel.plan?.buttonTitle ?? "Apply") {
                    viewModel.apply(context: modelContext, commit: modelContext.save)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.operation == .subtract || viewModel.deleteTool ? .red : .accentColor)
                .disabled(!viewModel.canApply)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }
}

struct CSVOperationReviewScreen: View {
    @Bindable var viewModel: CardListOperationViewModel
    let onDone: () -> Void

    var body: some View {
        Form {
            Section("Inputs") {
                LabeledContent("Target", value: viewModel.target.name)
                LabeledContent("Tool", value: viewModel.plan?.toolName ?? "CSV")
            }
            CardListOperationReview(viewModel: viewModel)
        }
        .navigationTitle("Review Changes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            CardListOperationFooter(viewModel: viewModel, onDone: onDone)
        }
    }
}
