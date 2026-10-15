import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ResultsFeedbackIntegrationTests: FeedbackIntegrationTestCase {
    func testResultsBulkFinishActionCapturesEachSelectedResultAndUploads() async throws {
        let (context, first) = try feedbackFixture()
        let second = CollectionItem(from: first.toRecognizedCard())
        second.resultScanJPEG = first.resultScanJPEG
        second.originalRecognition = first.originalRecognition
        context.insert(second)
        try context.save()
        let recorder = FeedbackRecorder()
        recorder.acknowledge = true
        let app = recorder.app()
        app.modelContext = context
        var selectionBar: CardSelectionActionBar?
        let view = ResultsView(selection: [first.id, second.id], makeSelectionBar: { bar in
            selectionBar = bar
            return AnyView(bar)
        }).environment(app).environment(\.modelContext, context).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer {
            closeScanCountWindow(window)
            selectionBar = nil
        }
        try await waitForFeedback { selectionBar != nil }
        XCTAssertFalse(try XCTUnwrap(selectionBar).isEmpty)
        try XCTUnwrap(XCTUnwrap(selectionBar).onToggleFoil)()
        try await waitForFeedback { recorder.attempts.count == 2 }
        try await waitForFeedback { (try? context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>())) == 0 }
        XCTAssertTrue(first.foil)
        XCTAssertTrue(second.foil)
        XCTAssertEqual(Set(recorder.attempts.map { $0.0.eventID }).count, 2)
        XCTAssertTrue(recorder.attempts.allSatisfy { $0.1 == "feedback-test://configured" })
    }

    // Removing the Results row's actual finish callback or its retry must fail this test.
    func testResultsRowFinishActionCapturesAndAutomaticallyUploads() async throws {
        let (context, item) = try feedbackFixture()
        let recorder = FeedbackRecorder()
        recorder.acknowledge = true
        let app = recorder.app()
        app.modelContext = context
        let view = ResultsView().environment(app).environment(\.modelContext, context)
            .modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        var coordinator: CardRowContextMenuCoordinator?
        try await waitForFeedback {
            coordinator = feedbackViews(in: window).flatMap(\.interactions)
                .compactMap { ($0 as? UIContextMenuInteraction)?.delegate as? CardRowContextMenuCoordinator }.first
            return coordinator != nil
        }
        let installed = try XCTUnwrap(coordinator)
        let menu = installed.actions.menu(isFoil: installed.item.foil)
        let group = try XCTUnwrap(menu.children.first as? UIMenu)
        let action = try XCTUnwrap(group.children.first { $0.title == "Set as Foil" } as? UIAction)
        let button = UIButton(type: .system)
        button.addAction(action, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        try await waitForFeedback { recorder.attempts.count == 1 }
        try await waitForFeedback { (try? context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>())) == 0 }
        XCTAssertTrue(item.foil)
        XCTAssertEqual(recorder.attempts.first?.1, app.apiBaseURL)
        XCTAssertFalse(try XCTUnwrap(recorder.attempts.first).0.previousIdentification.foil)
        XCTAssertTrue(try XCTUnwrap(recorder.attempts.first).0.correctedIdentification.foil)
    }
}
