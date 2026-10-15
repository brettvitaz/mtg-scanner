import MTGScannerKit
import SwiftData
import SwiftUI
#if DEBUG
import MTGScannerFixtures
#endif

@main
struct MTGScannerApp: App {
    @State private var appModel: AppModel
    @State private var libraryViewModel = LibraryViewModel()

    private let modelContainer: ModelContainer
    #if DEBUG
    private let testSession: UITestSession?
    #endif

    init() {
        #if DEBUG
        testSession = Self.makeTestSession()
        _appModel = State(initialValue: testSession?.appModel ?? AppModel())
        modelContainer = testSession?.container ?? Self.productionContainer()
        #else
        _appModel = State(initialValue: AppModel())
        modelContainer = Self.productionContainer()
        #endif
        FontRegistry.registerAll()

        #if DEBUG
        if testSession != nil { return }
        #endif
        let cacheDir = URL.cachesDirectory.appending(path: "card-images")
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: cacheDir
        )
    }

    #if DEBUG
    private static func makeTestSession() -> UITestSession? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawID = environment["UI_TEST_RUN_ID"] else { return nil }
        guard let runID = UUID(uuidString: rawID),
              let rawMode = environment["UI_TEST_MODE"], let mode = UITestSession.Mode(rawValue: rawMode) else {
            fatalError("UI tests require a UUID run identifier and an explicit fresh/resume/cleanup mode")
        }
        UITestNetworkProtocol.install()
        do {
            return try UITestSession(runID: runID, mode: mode)
        } catch {
            fatalError("Unable to prepare UI-test state: \(error)")
        }
    }
    #endif

    private static func productionContainer() -> ModelContainer {
        let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if testSession?.mode == .cleanup {
                Text("UI test data removed").accessibilityIdentifier("ui-test-cleanup")
            } else if let testSession {
                UITestRootView(session: testSession).modelContainer(testSession.container)
            } else if let route = UserDefaults.standard.string(forKey: "UI_PREVIEW_ROUTE") {
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
