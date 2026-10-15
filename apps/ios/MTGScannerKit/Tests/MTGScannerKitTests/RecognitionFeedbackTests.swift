import SwiftData
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class RecognitionFeedbackTests: XCTestCase {
    func testEditorCapturesOriginalPreviousAndCorrectedOncePerChange() throws {
        let context = try context()
        let item = result(context)
        let draft = CardEditDraft(card: item.toRecognizedCard())
        let corrected = RecognizedCard(title: "Correct", edition: "New", collectorNumber: "42")
        draft.select(CardPrinting(card: corrected), foil: true)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://original.example"))
        var events = try context.fetch(FetchDescriptor<RecognitionFeedbackEvent>())
        XCTAssertEqual(events.count, 1)
        let first = try XCTUnwrap(events.first)
        XCTAssertEqual(first.baseURL, "https://original.example")
        let payload = try first.payload()
        XCTAssertEqual(payload.originalRecognition.title, "Wrong")
        XCTAssertEqual(payload.previousIdentification.title, "Wrong")
        XCTAssertEqual(payload.correctedIdentification.title, "Correct")
        XCTAssertTrue(payload.correctedIdentification.foil)
        XCTAssertEqual(payload.scanJPEG, item.resultScanJPEG)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://new.example"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
        draft.isFoil = false
        XCTAssertTrue(draft.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://new.example"))
        events = try context.fetch(FetchDescriptor<RecognitionFeedbackEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(try events.allSatisfy { try $0.payload().originalRecognition.title == "Wrong" })
        XCTAssertTrue(try events.contains { try $0.payload().previousIdentification.title == "Correct" })
    }

    func testUnchangedQuantityOnlyAndMissingEvidenceCreateNoEvent() throws {
        let context = try context()
        let item = result(context)
        let unchanged = CardEditDraft(card: item.toRecognizedCard())
        item.quantity = 5
        XCTAssertTrue(unchanged.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://example.com"))
        item.resultScanJPEG = nil
        unchanged.isFoil = true
        XCTAssertTrue(unchanged.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://example.com"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
    }

    func testFailedEditorSaveRollsBackIdentificationAndEvent() throws {
        let context = try context()
        let item = result(context)
        try context.save()
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.isFoil = true
        XCTAssertFalse(draft.save(item: item, context: context, merge: false,
                                 feedbackBaseURL: "https://example.com",
                                  commit: { throw URLError(.cannotWriteToFile) }))
        XCTAssertFalse(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
        XCTAssertNotNil(draft.errorMessage)
    }

    func testResultsFinishShortcutCapturesAndRollsBackOnFailure() throws {
        let context = try context()
        let item = result(context)
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "https://example.com")
        XCTAssertTrue(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
        XCTAssertThrowsError(try ResultCorrectionSave.toggleFoil(
            items: [item], context: context, baseURL: "https://example.com",
            commit: { throw URLError(.cannotWriteToFile) }
        ))
        XCTAssertTrue(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
    }

    func testOutboxSurvivesRestartDeletionFailureThenAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "feedback.store")
        do {
            let context = try context(url)
            let item = result(context)
            try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "https://captured.example")
            context.delete(item)
            try context.save()
        }
        let reopened = try context(url)
        let failing = RecognitionFeedbackUploader(upload: { _, _ in throw URLError(.notConnectedToInternet) })
        await failing.retry(context: reopened)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
        let uploader = RecognitionFeedbackUploader(upload: { payload, baseURL in
            XCTAssertEqual(baseURL, "https://captured.example")
            XCTAssertEqual(payload.originalRecognition.title, "Wrong")
            XCTAssertEqual(payload.correctedIdentification.foil, true)
            return payload.eventID
        })
        await uploader.retry(context: reopened)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<CollectionItem>()), 0)
        let acknowledged = try self.context(url)
        XCTAssertEqual(try acknowledged.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
    }

    func testMismatchedAcknowledgementKeepsEvent() async throws {
        let context = try context()
        let item = result(context)
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "https://example.com")
        let uploader = RecognitionFeedbackUploader(upload: { _, _ in UUID() })
        await uploader.retry(context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 1)
    }

    func testCorrectionsSavedDuringUploadDrainWithoutAnotherActivation() async throws {
        let context = try context()
        let item = result(context)
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "https://example.com")
        let gate = FeedbackUploadGate()
        defer { Task { await gate.finish() } }
        let uploader = RecognitionFeedbackUploader(upload: { payload, _ in await gate.upload(payload.eventID) })
        let task = Task { await uploader.retry(context: context) }
        try await gate.waitUntilStarted()
        try ResultCorrectionSave.toggleFoil(items: [item], context: context, baseURL: "https://example.com")
        await uploader.retry(context: context)
        await gate.finish()
        await task.value
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
    }

    private func context(_ url: URL? = nil) throws -> ModelContext {
        let configuration = url.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self,
                                          RecognitionFeedbackEvent.self, configurations: configuration)
        return ModelContext(container)
    }

    private func result(_ context: ModelContext) -> CollectionItem {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
        }
        let card = RecognizedCard(title: "Wrong", edition: "Unknown", foil: false, confidence: 0.4,
                                  cropImageData: image.jpegData(compressionQuality: 1)?.base64EncodedString())
        let item = CollectionItem(from: card)
        item.attachResultEvidence(from: card)
        context.insert(item)
        return item
    }
}

private actor FeedbackUploadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var attempts = 0

    func upload(_ id: UUID) async -> UUID {
        attempts += 1
        if attempts == 1 { await withCheckedContinuation { continuation = $0 } }
        return id
    }

    func waitUntilStarted() async throws {
        for _ in 0..<200 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
