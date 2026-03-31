import SwiftData
import SwiftUI

@main
struct MTGScannerApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var libraryViewModel = LibraryViewModel()

    init() {
        let cacheDir = URL.cachesDirectory.appending(path: "card-images")
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: cacheDir
        )
    }

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
