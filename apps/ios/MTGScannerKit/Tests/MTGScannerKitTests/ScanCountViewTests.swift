import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ScanCountViewTests: XCTestCase {
    func testScanAppearanceConnectsRecognitionToSharedBadge() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        app.modelContext = context
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: [RecognizedCard(title: "Island", edition: "Test")])
        })
        let model = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        let view = ScanView(detectionMode: .constant(.scan), isActive: true, autoScanViewModel: model)
            .environment(app).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window); queue.cancelAll() }
        try await waitForScanCount { model.modelContext != nil }
        let payload = RecognitionImagePayload(displayImage: UIImage(), uploadData: Data([1]),
                                              contentType: "image/jpeg", preferredFilenameExtension: "jpg")
        await model.enqueueCapturedImage(payload, cropEnabled: false)
        try await waitForScanCount { queue.pendingCount == 0 }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 1)
        XCTAssertEqual(app.newlyScannedCardCount, 1)
        XCTAssertEqual(app.resultsBadgeText, "1")
    }

    func testBackgroundAndForegroundKeepOutstandingBadge() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        app.modelContext = context
        app.recordScannedCard()
        app.recordScannedCard()
        let phase = ScanCountSceneState()
        let model = AutoScanViewModel(detectorProvider: { nil })
        let view = ScanCountSceneView(app: app, model: model, phase: phase)
            .modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { model.modelContext != nil }
        for nextPhase in [ScenePhase.inactive, .background, .inactive, .active] {
            phase.value = nextPhase
            // Allow SwiftUI to deliver the environment change to the production lifecycle handler.
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(app.newlyScannedCardCount, 2)
            XCTAssertEqual(app.resultsBadgeText, "2")
        }
    }
}

@MainActor
@Observable
private final class ScanCountSceneState {
    var value = ScenePhase.active
}

private struct ScanCountSceneView: View {
    let app: AppModel
    let model: AutoScanViewModel
    let phase: ScanCountSceneState

    var body: some View {
        ScanView(detectionMode: .constant(.scan), isActive: true, autoScanViewModel: model)
            .environment(app).environment(\.scenePhase, phase.value)
    }
}

@MainActor
func makeScanCountWindow(view: some View) -> UIWindow {
    let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
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

@MainActor
func closeScanCountWindow(_ window: UIWindow) {
    window.isHidden = true
    window.rootViewController = nil
}

@MainActor
func waitForScanCount(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Scan count condition did not settle")
}
