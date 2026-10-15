import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ResultEditorIntegrationTests: FeedbackIntegrationTestCase {
    // Removing CardDetailView's production save callback or backend argument must fail this test.
    func testProductionEditorSaveCapturesAndStartsUploadBeforeAcknowledgement() async throws {
        let (context, item) = try feedbackFixture()
        let recorder = FeedbackRecorder()
        defer { recorder.acknowledge = true }
        let app = recorder.app()
        app.modelContext = context
        app.apiBaseURL = "feedback-test://configured"
        let draft = CardEditDraft(card: item.toRecognizedCard())
        let window = try await editor(item, draft: draft, context: context, app: app)
        defer { closeFeedbackEditorWindow(window) }
        draft.isFoil = true
        try activateFeedbackButton(XCTUnwrap(feedbackToolbarButton(in: window, title: "Save")))
        try await waitForFeedback { recorder.attempts.count == 1 }
        XCTAssertTrue(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
        let (payload, baseURL) = try XCTUnwrap(recorder.attempts.first)
        XCTAssertEqual(baseURL, "feedback-test://configured")
        XCTAssertEqual(payload.originalRecognition.title, "Island")
        XCTAssertFalse(payload.previousIdentification.foil)
        XCTAssertTrue(payload.correctedIdentification.foil)
        XCTAssertEqual(payload.scanJPEG, item.resultScanJPEG)
        recorder.acknowledge = true
        try await waitForFeedback { (try? context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>())) == 0 }
    }

    func testProductionEditorCancelAndUnchangedSaveDoNotCapture() async throws {
        for cancel in [true, false] {
            let (context, item) = try feedbackFixture()
            let recorder = FeedbackRecorder()
            recorder.acknowledge = true
            let app = recorder.app()
            app.modelContext = context
            let draft = CardEditDraft(card: item.toRecognizedCard())
            let window = try await editor(item, draft: draft, context: context, app: app)
            defer { closeFeedbackEditorWindow(window) }
            draft.isFoil = cancel
            let title = cancel ? "Cancel" : "Save"
            try activateFeedbackButton(XCTUnwrap(feedbackToolbarButton(in: window, title: title)))
            await Task.yield()
            XCTAssertFalse(item.foil)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
            XCTAssertTrue(recorder.attempts.isEmpty)
        }
    }

    func testProductionEditorFailedSaveKeepsEditorAndRollsBackCapture() async throws {
        let (context, item) = try feedbackFixture()
        let recorder = FeedbackRecorder()
        recorder.acknowledge = true
        let app = recorder.app()
        app.modelContext = context
        let draft = CardEditDraft(card: item.toRecognizedCard(), commit: { throw URLError(.cannotWriteToFile) })
        let window = try await editor(item, draft: draft, context: context, app: app)
        defer { closeFeedbackEditorWindow(window) }
        draft.isFoil = true
        try activateFeedbackButton(XCTUnwrap(feedbackToolbarButton(in: window, title: "Save")))
        XCTAssertNotNil(draft.errorMessage)
        XCTAssertNotNil(feedbackToolbarButton(in: window, title: "Save"))
        XCTAssertFalse(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
        XCTAssertTrue(recorder.attempts.isEmpty)
    }

    private func editor(_ item: CollectionItem, draft: CardEditDraft, context: ModelContext,
                        app: AppModel) async throws -> UIWindow {
        let view = NavigationStack {
            CardDetailView(card: item.toRecognizedCard(), resultScope: true, editorDraft: draft)
        }.environment(app).environment(\.modelContext, context).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        do {
            try await waitForFeedback { feedbackToolbarButton(in: window, title: "Edit") != nil }
            try activateFeedbackButton(XCTUnwrap(feedbackToolbarButton(in: window, title: "Edit")))
            try await waitForFeedback { window.rootViewController?.presentedViewController != nil }
            let presented = try XCTUnwrap(window.rootViewController?.presentedViewController)
            // Headless package hosts present the controller without attaching its view to a scene.
            presented.view.frame = window.bounds
            window.addSubview(presented.view)
            presented.beginAppearanceTransition(true, animated: false)
            presented.endAppearanceTransition()
            presented.view.layoutIfNeeded()
            try await waitForFeedback { feedbackToolbarButton(in: window, title: "Save") != nil }
            return window
        } catch {
            closeFeedbackEditorWindow(window)
            throw error
        }
    }
}

@MainActor
private func closeFeedbackEditorWindow(_ window: UIWindow) {
    window.rootViewController?.dismiss(animated: false)
    closeScanCountWindow(window)
}
