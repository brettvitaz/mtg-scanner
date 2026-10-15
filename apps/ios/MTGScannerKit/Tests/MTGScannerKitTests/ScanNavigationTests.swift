import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ScanNavigationTests: XCTestCase {
    func testActiveAndWaitingRecognitionPersistResultsAfterNavigation() async throws {
        let container = try makeContainer()
        let gate = SuspendedRecognition()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in await gate.run() })
        queue.maxConcurrent = 1
        let model = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        model.modelContext = container.mainContext
        await model.enqueueCapturedImage(makePayload(), cropEnabled: false)
        await model.enqueueCapturedImage(makePayload(), cropEnabled: false)
        await waitUntil { await gate.isWaiting }
        XCTAssertEqual(queue.pendingCount, 2)
        model.pauseForNavigation()
        await gate.finish()
        await waitUntil { await gate.isWaiting }
        await gate.finish()
        await waitUntil { queue.pendingCount == 0 }
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.map(\.title), ["Lightning Bolt", "Lightning Bolt"])
        XCTAssertTrue(items.allSatisfy { $0.collection == nil && $0.deck == nil })
        XCTAssertEqual(queue.completedCount, 2)
        XCTAssertEqual(queue.failedCount, 0)
    }

    func testStandardPhotoCroppingContinuesAfterNavigation() async throws {
        let container = try makeContainer()
        let crop = NavigationCrop()
        let queue = RecognitionQueue(
            recognizeBatch: { _, _, _ in RecognitionResult.sample }
        )
        let model = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            cropImage: { _, _ in await crop.run() }
        )
        model.modelContext = container.mainContext
        let payload = makePayload()
        let processing = Task { await model.enqueueCapturedImage(payload, cropEnabled: true) }
        await waitUntil { await crop.isWaiting }
        model.pauseForNavigation()
        await crop.finish(payload.displayImage)
        await processing.value
        await waitUntil { queue.completedCount == 1 }
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.map(\.title), ["Lightning Bolt"])
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testScanViewTabInactivityAndDisappearancePreserveCapture() async throws {
        let container = try makeContainer()
        let app = AppModel()
        app.modelContext = container.mainContext
        let photo = NavigationPhoto()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult.sample })
        let model = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { await photo.run() }
        )
        let state = NavigationState()
        let view = NavigationHost(state: state, model: model).environment(app).modelContainer(container)
        let window = show(view)
        defer { window.isHidden = true }
        await waitUntil { model.modelContext != nil }
        model.start()
        model.captureManually()
        await waitUntil { photo.isWaiting }
        state.isActive = false
        await waitUntil { !model.isActive }
        state.showsScan = false
        await waitUntil { window.rootViewController?.children.isEmpty == true }
        photo.finish(makePayload())
        await waitUntil { queue.completedCount == 1 }
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.map(\.title), ["Lightning Bolt"])
        XCTAssertFalse(model.isActive)
        XCTAssertNil(model.lastCroppedImage)
        XCTAssertFalse(model.isCalibrated)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CardCollection.self, Deck.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makePayload() -> RecognitionImagePayload {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return .cameraCapture(image: image, data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    private func show(_ view: some View) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        controller.view.layoutIfNeeded()
        return window
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Navigation processing did not reach the expected state")
    }
}

@MainActor
@Observable
private final class NavigationState {
    var isActive = true
    var showsScan = true
}

private struct NavigationHost: View {
    let state: NavigationState
    let model: AutoScanViewModel

    var body: some View {
        if state.showsScan {
            ScanView(detectionMode: .constant(.auto), isActive: state.isActive, autoScanViewModel: model)
        } else {
            Text("Results")
        }
    }
}

@MainActor
private final class NavigationPhoto {
    private var continuation: CheckedContinuation<RecognitionImagePayload?, Never>?
    var isWaiting: Bool { continuation != nil }

    func run() async -> RecognitionImagePayload? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ payload: RecognitionImagePayload) {
        continuation?.resume(returning: payload)
        continuation = nil
    }
}

private actor NavigationCrop {
    private var continuation: CheckedContinuation<CardCropResult, Never>?
    var isWaiting: Bool { continuation != nil }

    func run() async -> CardCropResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ image: UIImage) {
        continuation?.resume(returning: CardCropResult(crops: [image], detectedCount: 1))
        continuation = nil
    }
}

private actor SuspendedRecognition {
    private var continuation: CheckedContinuation<RecognitionResult, Never>?
    var isWaiting: Bool { continuation != nil }

    func run() async -> RecognitionResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: RecognitionResult.sample)
        continuation = nil
    }
}
