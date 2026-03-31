import SwiftData
import SwiftUI

@main
struct MTGScannerApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var libraryViewModel = LibraryViewModel()

    let modelContainer: ModelContainer = {
        let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .environmentObject(libraryViewModel)
                .modelContainer(modelContainer)
                .onAppear {
                    appModel.modelContext = modelContainer.mainContext
                    libraryViewModel.modelContext = modelContainer.mainContext
                }
        }
    }
}
