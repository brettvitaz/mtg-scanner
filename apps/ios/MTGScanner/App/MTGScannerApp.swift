import MTGScannerKit
import SwiftData
import SwiftUI
#if DEBUG
import MTGScannerFixtures
#endif

@main
struct MTGScannerApp: App {
    @State private var appModel = AppModel()
    @State private var libraryViewModel = LibraryViewModel()

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
            #if DEBUG
            if let route = UserDefaults.standard.string(forKey: "UI_PREVIEW_ROUTE") {
                PreviewGalleryRootView(route: route)
            } else {
                rootTabView
            }
            #else
            rootTabView
            #endif
        }
    }

    private var rootTabView: some View {
        RootTabView()
            .environment(appModel)
            .environment(libraryViewModel)
            .modelContainer(modelContainer)
            .onAppear {
                appModel.modelContext = modelContainer.mainContext
                libraryViewModel.modelContext = modelContainer.mainContext
            }
    }
}
