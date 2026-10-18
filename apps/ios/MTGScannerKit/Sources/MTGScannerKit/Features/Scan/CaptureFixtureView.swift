#if DEBUG
import OSLog
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
    private var hasHeldMotion = false

    init(route: String, binderData: Data, cardData: Data) {
        self.route = route
        let accessibility = "reduceMotion=\(UIAccessibility.isReduceMotionEnabled) " +
            "reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled) " +
            "increaseContrast=\(UIAccessibility.isDarkerSystemColorsEnabled)"
        Logger(subsystem: "com.mtgscanner", category: "CaptureFixture")
            .notice("route=\(route, privacy: .public) \(accessibility, privacy: .public)")
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
        app.selectTab(route.hasPrefix("capture-station-") || route.hasPrefix("capture-zoom-pinch-") ? .station : .table)
        container = try? ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self, RecognitionFeedbackEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        app.modelContext = container?.mainContext
        library.modelContext = container?.mainContext
        for camera in [tableCamera, stationCamera] {
            camera.zoomDevice = CameraZoomDevice(maximum: 4, change: { _, authorize, complete in
                complete(authorize())
            })
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
                AnyView(CaptureFixturePreview(image: isStation ? card : binder, scene: binder,
                                              background: previewBackground, camera: camera)
                    .onAppear { preview.connect(camera) })
            },
            opensBrightness: active && (route.hasPrefix("capture-brightness") || route == "capture-station-brightness"),
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
            seedStation(model)
            seedZoom(mode: mode)
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

    private func seedZoom(mode: DetectionMode) {
        let camera = mode == .auto ? stationCamera : tableCamera
        switch route {
        case "capture-table-binder", "capture-zoom-open", "capture-zoom-menu": camera.setZoom(1.5)
        case "capture-zoom-pinch-low": modelFor(mode).start(); camera.setZoom(1.9)
        case "capture-zoom-pinch-high": modelFor(mode).start(); camera.setZoom(2.1)
        case "capture-zoom-pinch-upper": modelFor(mode).start(); camera.setZoom(3.2)
        case "capture-zoom-transition", "capture-station-zoom-transition":
            camera.scheduleZoomFrame = { [weak self, weak camera] work in
                guard let self, let camera else { return }
                if !self.hasHeldMotion && camera.appliedZoom >= 1.25 {
                    self.hasHeldMotion = true
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
            }
            camera.setZoom(1.5, animated: true)
        default: break
        }
    }

    private func modelFor(_ mode: DetectionMode) -> AutoScanViewModel { mode == .auto ? station : table }

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
private struct CaptureFixturePreview: View {
    let image: UIImage
    let scene: UIImage
    let background: Color
    let camera: CameraViewController
    @State private var pinching = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: scene).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                background.opacity(0.8)
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityIdentifier("capture-fixture-pinch-target")
                    .frame(width: geometry.size.width * 0.88, height: geometry.size.height * 0.65)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)
            }
            .contentShape(Rectangle())
            .gesture(MagnifyGesture().onChanged { value in
                if !pinching { camera.beginPinch(); pinching = true }
                camera.applyPinch(scale: value.magnification)
            }.onEnded { _ in camera.endPinch(); pinching = false })
        }
    }
}
#endif
