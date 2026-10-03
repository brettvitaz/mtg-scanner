import SwiftUI

struct CardListOperationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CardListOperationViewModel
    @State private var path: [CardListPickerRole] = []

    init(target: CardListReference, viewModel: CardListOperationViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? CardListOperationViewModel(target: target))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if viewModel.receipt == nil {
                    inputs
                }
                if viewModel.tool != nil || viewModel.receipt != nil {
                    CardListOperationReview(viewModel: viewModel)
                }
            }
            .navigationTitle("Apply a List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.receipt == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .navigationDestination(for: CardListPickerRole.self) { role in
                CardListPicker(role: role, excludedID: role == .tool ? viewModel.target.id : nil) { list in
                    if role == .target { viewModel.chooseTarget(list) } else { viewModel.chooseTool(list) }
                    path.removeLast()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.tool != nil || viewModel.receipt != nil {
                    CardListOperationFooter(viewModel: viewModel) { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isApplying)
    }

    private var inputs: some View {
        Section {
            NavigationLink(value: CardListPickerRole.target) {
                input("Target", list: viewModel.target)
            }
            NavigationLink(value: CardListPickerRole.tool) {
                input("Tool", list: viewModel.tool)
            }
        } header: {
            Text("Lists")
        } footer: {
            if viewModel.tool == nil {
                Text("Choose the target first, then a tool. Target receives changes; tool supplies quantities.")
            }
        }
    }

    private func input(_ label: String, list: CardListReference?) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(list?.name ?? "Choose a list").foregroundStyle(.primary)
                if let list {
                    Text("\(list.kind.rawValue) · \(list.quantitySummary)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}
