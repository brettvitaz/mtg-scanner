import SwiftData
import SwiftUI
import XCTest
@testable import MTGScannerKit

@MainActor
final class FeedbackLifecycleIntegrationTests: FeedbackIntegrationTestCase {
    // Removing the root's initial drain must leave the saved event queued and fail this test.
    func testRootAppearanceUploadsPendingEvidenceUsingStoredDestination() async throws {
        let (context, item) = try feedbackFixture()
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "feedback-test://original")
        let recorder = FeedbackRecorder()
        recorder.acknowledge = true
        let app = recorder.app()
        app.selectTab(.settings)
        let phase = FeedbackScenePhase()
        let window = makeScanCountWindow(view: FeedbackRoot(app: app, phase: phase)
            .environment(\.modelContext, context).modelContainer(context.container))
        defer { closeScanCountWindow(window) }
        try await waitForFeedback { recorder.attempts.count == 1 }
        try await waitForFeedback { (try? context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>())) == 0 }
        XCTAssertTrue(app.modelContext === context)
        XCTAssertEqual(recorder.attempts.first?.1, "feedback-test://original")
        XCTAssertTrue(recorder.attempts.first?.0.correctedIdentification.foil == true)
    }

    // Removing scene activation retry must strand the failed launch attempt and fail this test.
    func testActivationRetriesFailedUploadWithoutChangingCapturedBackend() async throws {
        let (context, item) = try feedbackFixture()
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "feedback-test://original")
        let recorder = FeedbackRecorder()
        recorder.fail = true
        let app = recorder.app()
        app.selectTab(.settings)
        let phase = FeedbackScenePhase()
        let window = makeScanCountWindow(view: FeedbackRoot(app: app, phase: phase)
            .environment(\.modelContext, context).modelContainer(context.container))
        defer { closeScanCountWindow(window) }
        try await waitForFeedback { recorder.attempts.count == 1 }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
        recorder.fail = false
        recorder.acknowledge = true
        phase.value = .active
        try await waitForFeedback { recorder.attempts.count == 2 }
        try await waitForFeedback { (try? context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>())) == 0 }
        XCTAssertEqual(recorder.attempts.map(\.1), ["feedback-test://original", "feedback-test://original"])
    }
}

@MainActor
@Observable
private final class FeedbackScenePhase {
    var value = ScenePhase.inactive
}

private struct FeedbackRoot: View {
    let app: AppModel
    let phase: FeedbackScenePhase
    @State private var library = LibraryViewModel()

    var body: some View {
        RootTabView().environment(app).environment(library).environment(\.scenePhase, phase.value)
    }
}
