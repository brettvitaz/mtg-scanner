import SwiftData
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ResultScanEvidenceTests: XCTestCase {
    func testSingleEndpointResponsePersistsScanAndCapturesCorrectionAfterRestart() throws {
        let resource = try XCTUnwrap(Bundle.module.url(forResource: "hand-held-single-response", withExtension: "json"))
        let response = try JSONDecoder().decode(RecognitionResult.self, from: Data(contentsOf: resource))
        let card = try XCTUnwrap(response.cards.first)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "single-result.store")
        do {
            let container = try store(url)
            let app = AppModel()
            app.modelContext = container.mainContext
            app.latestResult = response
            app.persistRecognizedCards()
            try container.mainContext.save()
        }
        let container = try store(url)
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertNotNil(item.resultScanImage)
        XCTAssertEqual(item.resultScanJPEG, ResultScanEvidence.prepare(base64: card.cropImageData))
        let original = try JSONDecoder().decode(RecognizedCard.self, from: XCTUnwrap(item.originalRecognition))
        XCTAssertEqual(original.title, card.title)
        XCTAssertNil(original.cropImageData)
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.isFoil = !item.foil
        XCTAssertTrue(draft.save(item: item, context: context, merge: false,
                                feedbackBaseURL: "https://feedback.example"))
        let events = try context.fetch(FetchDescriptor<RecognitionFeedbackEvent>())
        XCTAssertEqual(events.count, 1)
        let payload = try XCTUnwrap(events.first).payload()
        XCTAssertEqual(payload.scanJPEG, item.resultScanJPEG)
        XCTAssertEqual(payload.originalRecognition.title, card.title)
        XCTAssertNotEqual(payload.previousIdentification.foil, payload.correctedIdentification.foil)
    }

    func testManualPersistenceReopensWithEachResponseCrop() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "results.store")
        let cards = [card("First", color: .red), card("Second", color: .blue)]
        do {
            let container = try store(url)
            let app = AppModel()
            app.modelContext = container.mainContext
            app.latestResult = RecognitionResult(cards: cards)
            // Positional client crops must never override response-owned evidence.
            app.lastDetectedCrops = [image(.green)]
            app.persistRecognizedCards()
            try container.mainContext.save()
        }
        let container = try store(url)
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 2)
        for item in items {
            let jpeg = try XCTUnwrap(item.resultScanJPEG)
            let pixel = try XCTUnwrap(UIImage(data: jpeg)?.cgImage?.dataProvider?.data)
            XCTAssertGreaterThan(CFDataGetLength(pixel), 0)
            let original = try JSONDecoder().decode(RecognizedCard.self, from: XCTUnwrap(item.originalRecognition))
            XCTAssertEqual(original.title, item.title)
            XCTAssertNil(original.cropImageData)
            let expected = item.title == "First" ? cards[0] : cards[1]
            XCTAssertEqual(jpeg, ResultScanEvidence.prepare(base64: expected.cropImageData))
        }
    }

    func testAutoScanPersistenceReopensWithEachResponseCrop() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "results.store")
        let cards = [card("First", color: .red), card("Second", color: .blue)]
        do {
            let container = try store(url)
            let queue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: cards) })
            queue.enqueue(image: image(.green), apiBaseURL: "https://example.com", modelContext: container.mainContext)
            for _ in 0..<200 where queue.pendingCount > 0 { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(queue.completedCount, 1)
            try container.mainContext.save()
        }
        let container = try store(url)
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 2)
        for item in items {
            let expected = item.title == "First" ? cards[0] : cards[1]
            XCTAssertEqual(item.resultScanJPEG, ResultScanEvidence.prepare(base64: expected.cropImageData))
            XCTAssertNotNil(item.originalRecognition)
        }
    }

    func testPreparationPreservesBoundsNormalizesOrientationAndNeverUpscales() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1400)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1400))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 1300, width: 800, height: 100))
        }
        let cgImage = try XCTUnwrap(source.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        let jpeg = try XCTUnwrap(ResultScanEvidence.prepare(image: rotated))
        let prepared = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(prepared.imageOrientation, .up)
        XCTAssertEqual(prepared.size.width, 1000, accuracy: 1)
        XCTAssertEqual(prepared.size.height, 571, accuracy: 1)
        let pixels = try XCTUnwrap(prepared.cgImage)
        let strip = try XCTUnwrap(pixels.cropping(to: CGRect(x: 0, y: 0, width: 30, height: 500)))
        let data = try XCTUnwrap(strip.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertGreaterThan(bytes[2], bytes[0], "Bottom card boundary must remain blue after rotation")
        let small = try XCTUnwrap(ResultScanEvidence.prepare(image: image(.green)))
        XCTAssertEqual(UIImage(data: small)?.size, CGSize(width: 100, height: 140))
        XCTAssertNil(ResultScanEvidence.prepare(base64: "invalid"))
    }

    func testRealCropsRetainCollectorAreaForVisualReview() throws {
        let names = ["table-good-teferis-protection", "auto-good-kruphix-god-of-horizons",
                     "auto-good-cauldrons-of-souls"]
        let directory = FileManager.default.temporaryDirectory.appending(path: "result-evidence-visual-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg"))
            let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url)))
            let jpeg = try XCTUnwrap(ResultScanEvidence.prepare(image: image))
            let prepared = try XCTUnwrap(UIImage(data: jpeg))
            XCTAssertLessThanOrEqual(max(prepared.size.width, prepared.size.height), 1000)
            XCTAssertEqual(prepared.size.width / prepared.size.height, image.size.width / image.size.height,
                           accuracy: 0.002)
            try jpeg.write(to: directory.appending(path: name + ".jpg"))
        }
        print("Result evidence validation JPEGs: \(directory.path)")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func store(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self, RecognitionFeedbackEvent.self,
                           configurations: ModelConfiguration(url: url))
    }

    private func card(_ title: String, color: UIColor) -> RecognizedCard {
        RecognizedCard(title: title, edition: "Test", collectorNumber: "123", confidence: 0.4,
                       cropImageData: image(color).jpegData(compressionQuality: 1)?.base64EncodedString())
    }

    private func image(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
        }
    }
}
