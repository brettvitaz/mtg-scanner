#if DEBUG
import SwiftData
import SwiftUI

public struct ResultsCountFixtureView: View {
    private let route: String
    private let appModel: AppModel
    private let container: ModelContainer?
    private let setupError: String?

    public init(route: String) {
        self.route = route
        let defaults = UserDefaults.standard
        let count = defaults.object(forKey: "scan_session_count")
        let mode = defaults.object(forKey: "results_count_mode")
        defer {
            defaults.set(count, forKey: "scan_session_count")
            defaults.set(mode, forKey: "results_count_mode")
        }
        defaults.set(route == "scan-count-zero" ? 0 : route == "scan-count-overflow" ? 1000 : 24,
                     forKey: "scan_session_count")
        defaults.set("session", forKey: "results_count_mode")
        appModel = AppModel()
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            appModel.modelContext = container.mainContext
            self.container = container
            setupError = nil
        } catch {
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            content.modelContainer(container).environment(appModel).environment(LibraryViewModel())
        } else {
            Text(setupError ?? "Unable to load scan count fixture.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if route == "scan-count-reset" {
            RootTabView(previewScanModePicker: true)
        } else if route == "scan-count-settings" {
            SettingsView()
        } else {
            RootTabView().task { appModel.shouldShowResults = true }
        }
    }
}
#endif
