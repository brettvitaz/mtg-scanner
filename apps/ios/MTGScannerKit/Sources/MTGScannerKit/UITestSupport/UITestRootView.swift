#if DEBUG
import SwiftData
import SwiftUI

/// Only the entry list is test scaffolding; detail and editor use production views.
public struct UITestRootView: View {
    private let session: UITestSession
    @Query private var items: [CollectionItem]

    public init(session: UITestSession) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink {
                    CardDetailView(card: item.toRecognizedCard())
                } label: {
                    Text(item.title)
                }
                .accessibilityIdentifier("ui-test-saved-card")
            }
            .navigationTitle("Saved Cards")
        }
        .environment(session.appModel)
    }
}
#endif
