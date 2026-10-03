import SwiftUI

struct CSVOperationReviewScreen: View {
    @Bindable var viewModel: CardListOperationViewModel
    let onDone: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            if viewModel.receipt == nil {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(viewModel.target.name).font(CSVImportStyle.heading)
                        Text(viewModel.plan?.toolName ?? "CSV")
                            .font(CSVImportStyle.metadata).foregroundStyle(CSVImportStyle.secondaryText)
                    }
                }
                .listRowBackground(Color.dsBackground)
                .listRowSeparator(.hidden)
            }
            CardListOperationReview(viewModel: viewModel)
                .listRowBackground(Color.dsBackground)
            if dynamicTypeSize.isAccessibilitySize {
                Section { footer }.listRowInsets(EdgeInsets())
            }
        }
        .modifier(CSVImportListStyle())
        .navigationTitle("Review Changes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                footer.frame(maxWidth: CSVImportStyle.contentWidth)
                    .frame(maxWidth: .infinity).background(.bar)
            }
        }
    }

    private var footer: some View {
        CardListOperationFooter(viewModel: viewModel, onDone: onDone)
    }
}
