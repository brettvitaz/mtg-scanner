#if DEBUG
import SwiftData
import SwiftUI

/// The production tab shell and controls with inert camera/capture dependencies.
public struct CaptureFixtureView: View {
    @State private var state: CaptureFixtureState

    public init(route: String, binderData: Data, cardData: Data) {
        _state = State(initialValue: CaptureFixtureState(route: route, binderData: binderData, cardData: cardData))
    }

    public var body: some View {
        if let container = state.container {
            RootTabView { mode, active in
                AnyView(state.captureView(mode: mode, active: active))
            }
            .environment(state.app)
            .environment(state.library)
            .modelContainer(container)
        } else {
            Text("Capture fixture could not create its isolated store.")
        }
    }
}

@MainActor
@Observable
private final class CaptureFixtureState {
    let app: AppModel
    let library = LibraryViewModel()
    let container: ModelContainer?
    let route: String
    let binder: UIImage
    let card: UIImage
    let previewBackground: Color = ProcessInfo.processInfo.environment["CAPTURE_FIXTURE_BACKGROUND"] == "bright"
        ? .white : .black
    let table = AutoScanViewModel(
        detectorProvider: { nil }, recognitionQueue: RecognitionQueue(
            recognize: { _, _, _, _ in throw URLError(.notConnectedToInternet) },
            recognizeBatch: { _, _, _ in throw URLError(.notConnectedToInternet) }
        ),
        identifiedCardsViewModel: IdentifiedCardsViewModel(displayDuration: 60)
    )
    var station: AutoScanViewModel { table }
    let tableDetection = CardDetectionViewModel()
    let stationDetection = CardDetectionViewModel()
    let tableCoordinator = CameraCaptureCoordinator()
    let stationCoordinator = CameraCaptureCoordinator()
    let tableCamera = CameraViewController()
    let stationCamera = CameraViewController()
    private var seeded = false

    init(route: String, binderData: Data, cardData: Data) {
        self.route = route
        binder = UIImage(data: binderData) ?? UIImage()
        card = UIImage(data: cardData) ?? UIImage()
        // A volatile preferences domain never changes the user's settings.
        guard let preferences = UserDefaults(suiteName: "capture-fixture-\(UUID())") else {
            app = AppModel()
            container = nil
            return
        }
        app = AppModel(preferences: preferences)
        app.showRecognitionNotifications = route != "capture-recognition-disabled"
        app.lastTorchLevel = route == "capture-brightness-adjusted" ? 0.48 : 0.5
        app.selectTab(route.hasPrefix("capture-station-") ? .station : .table)
        container = try? ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self, RecognitionFeedbackEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        app.modelContext = container?.mainContext
        library.modelContext = container?.mainContext
        for camera in [tableCamera, stationCamera] {
            camera.zoomDevice = CameraZoomDevice(maximum: 4) { _ in true }
        }
    }

    func captureView(mode: DetectionMode, active: Bool) -> some View {
        let isStation = mode == .auto
        let camera = isStation ? stationCamera : tableCamera
        return ScanView(
            detectionMode: .constant(mode), isActive: active,
            autoScanViewModel: isStation ? station : table,
            detectionViewModel: isStation ? stationDetection : tableDetection,
            captureCoordinator: isStation ? stationCoordinator : tableCoordinator,
            previewContent: { [binder, card, previewBackground] preview in
                AnyView(Image(uiImage: isStation ? card : binder)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(previewBackground)
                    .onAppear { preview.connect(camera) })
            },
            opensBrightness: active && route.hasPrefix("capture-brightness"),
            opensZoomMenu: active && route == "capture-zoom-menu",
            onConfigured: { [weak self] in if active { self?.seed(mode: mode) } }
        )
    }

    private func seed(mode: DetectionMode) {
        guard !seeded else { return }
        seeded = true
        let model = mode == .auto ? station : table
        model.recognitionQueue.maxConcurrent = 0
        model.captureDelay = 60
        model.captureFocusedPhoto = { [card] _ in
            try? await Task.sleep(for: .seconds(60))
            return .success(.cameraCapture(image: card, data: Data([1])))
        }
        Task { [weak self] in
            guard let self else { return }
            await model.enqueueCapturedImage(card, cropEnabled: false)
            model.recognitionQueue.cancelAll()
            tableCamera.setZoom(route == "capture-table-binder" ? 1.7 : 1)
            seedStation(model)
            if route == "capture-station-error" {
                model.recognitionQueue.maxConcurrent = 1
                await model.enqueueCapturedImage(card, cropEnabled: false)
            }
            if route.hasPrefix("capture-recognition-") {
                model.recognitionQueue.onCardIdentified?(
                    RecognizedCard(title: "Lightning Bolt", edition: "Foundations", collectorNumber: "199",
                                   foil: true, setCode: "fdn")
                )
            }
        }
    }

    private func seedStation(_ model: AutoScanViewModel) {
        guard route.hasPrefix("capture-station-"), route != "capture-station-stopped" else { return }
        model.start()
        switch route {
        case "capture-station-settling":
            model.presenceTracker.onNewCardSignal?(
                CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), model.scanSessionID
            )
        case "capture-station-capturing": model.captureManually()
        case "capture-station-paused": _ = model.prepareForZoomChange(from: 1, to: 1.5)
        case "capture-station-error":
            model.captureFocusedPhoto = { _ in .failure(.unavailable) }
            model.captureManually()
        default: break
        }
    }
}
#endif
