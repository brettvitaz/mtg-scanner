import SwiftData
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class CaptureNotificationTests: XCTestCase {
    func testCompletionsStackNewestFirstAndEvictOnlyTheFourthOldest() {
        let model = IdentifiedCardsViewModel()
        model.addCard(IdentifiedCard(from: RecognizedCard(title: "Island", edition: "Test")))
        model.addCard(IdentifiedCard(from: RecognizedCard(title: "Forest", edition: "Test")))
        model.addCard(IdentifiedCard(from: RecognizedCard(title: "Mountain", edition: "Test")))
        XCTAssertEqual(model.recentCards.map(\.title), ["Mountain", "Forest", "Island"])
        model.addCard(IdentifiedCard(from: RecognizedCard(title: "Plains", edition: "Test")))
        XCTAssertEqual(model.recentCards.map(\.title), ["Plains", "Mountain", "Forest"])
        model.clearAll()
    }
    func testStackedCompletionsExpireWithoutRemovingNewerNotices() async throws {
        let model = IdentifiedCardsViewModel(displayDuration: 0.4)
        let first = IdentifiedCard(from: RecognizedCard(title: "Island", edition: "Test"))
        let second = IdentifiedCard(from: RecognizedCard(title: "Forest", edition: "Test"))
        model.addCard(first)
        // Stagger arrivals so the second notice must outlive the first one's timer.
        try await Task.sleep(for: .milliseconds(200))
        model.addCard(second)
        try await waitForScanCount { !model.recentCards.contains { $0.id == first.id } }
        XCTAssertEqual(model.recentCards.map(\.title), ["Forest"])
        try await waitForScanCount { model.recentCards.isEmpty }
    }

    func testPreferenceSuppressesOnlyFeedbackWhileResultsAndCountsContinueOnEitherCaptureTab() async throws {
        let suite = "notifications-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let app = AppModel(preferences: preferences)
        XCTAssertTrue(app.showRecognitionNotifications)
        let context = try makeScanCountContext()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: [RecognizedCard(title: "Forest", edition: "Test")])
        })
        let model = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        model.appModel = app
        model.modelContext = context
        var announcements: [String] = []
        model.feedback.announce = { message, _ in announcements.append(message) }
        app.showRecognitionNotifications = false
        XCTAssertFalse(AppModel(preferences: preferences).showRecognitionNotifications)
        for tab in [AppTab.table, .station] {
            app.selectTab(tab)
            await model.enqueueCapturedImage(
                RecognitionImagePayload(displayImage: UIImage(), uploadData: Data([1]),
                                        contentType: "image/jpeg", preferredFilenameExtension: "jpg"),
                cropEnabled: false
            )
            try await waitForScanCount { queue.pendingCount == 0 }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 2)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
        XCTAssertTrue(model.identifiedCardsViewModel.recentCards.isEmpty)
        XCTAssertTrue(announcements.isEmpty)
        app.selectTab(.results)
        XCTAssertEqual(app.newlyScannedCardCount, 0)
        model.feedback.haptic = {}
        model.feedback.completed(ready: true)
        XCTAssertEqual(announcements.count, 1)
        XCTAssertTrue(announcements[0].contains("Ready for the next card"))
    }
    func testProductionCallbackQueuesRecognitionBehindReadiness() async throws {
        let suite = "notification-order-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let app = AppModel(preferences: preferences)
        let model = AutoScanViewModel(detector: nil)
        model.appModel = app
        var speeches: [(String, Bool)] = []
        model.feedback.haptic = {}
        model.feedback.announce = { speeches.append(($0, $1)) }
        model.recognitionQueue.onCardIdentified?(RecognizedCard(title: "Forest", edition: "Test"))
        model.feedback.completed(ready: true)
        XCTAssertEqual(speeches.count, 1)
        try await waitForScanCount { speeches.count == 2 }
        XCTAssertTrue(speeches[0].0.contains("Ready for the next card"))
        XCTAssertTrue(speeches[1].0.contains("Recognized Forest"))
        XCTAssertEqual(speeches.map(\.1), [false, true])
        model.feedback.cancelRecognition()
    }

    func testDisablingPreferenceSuppressesAlreadyScheduledRecognitionSpeech() async throws {
        let suite = "notification-cancel-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AutoScanViewModel(detector: nil)
        let app = AppModel(preferences: preferences)
        model.appModel = app
        let speech = expectation(description: "Disabled recognition must not speak")
        speech.isInverted = true
        model.feedback.announce = { _, _ in speech.fulfill() }
        model.recognitionQueue.onCardIdentified?(RecognizedCard(title: "Forest", edition: "Test"))
        app.showRecognitionNotifications = false
        await fulfillment(of: [speech], timeout: 1.2)
        XCTAssertEqual(model.identifiedCardsViewModel.recentCards.map(\.title), ["Forest"])
        XCTAssertEqual(app.newlyScannedCardCount, 1)
    }

}
