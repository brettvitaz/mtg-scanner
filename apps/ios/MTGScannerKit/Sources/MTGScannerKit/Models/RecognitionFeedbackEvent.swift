import Foundation
import SwiftData

struct FeedbackIdentification: Codable, Equatable, Sendable {
    let title: String
    let edition: String
    let foil: Bool
    let setCode: String?
    let collectorNumber: String?
    let scryfallID: String?

    init(_ item: CollectionItem) {
        title = item.title
        edition = item.edition
        foil = item.foil
        setCode = item.setCode?.nonEmpty
        collectorNumber = item.collectorNumber?.nonEmpty
        scryfallID = item.scryfallId?.nonEmpty
    }

    enum CodingKeys: String, CodingKey {
        case title, edition, foil
        case setCode = "set_code"
        case collectorNumber = "collector_number"
        case scryfallID = "scryfall_id"
    }
}

struct RecognitionFeedbackPayload: Codable, Sendable {
    let eventID: UUID
    let createdAt: String
    let originalRecognition: RecognizedCard
    let previousIdentification: FeedbackIdentification
    let correctedIdentification: FeedbackIdentification
    let scanJPEG: Data

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case createdAt = "created_at"
        case originalRecognition = "original_recognition"
        case previousIdentification = "previous_identification"
        case correctedIdentification = "corrected_identification"
        case scanJPEG = "scan_jpeg"
    }
}

@Model
public final class RecognitionFeedbackEvent {
    public var id: UUID
    public var createdAt: Date
    public var baseURL: String
    var originalRecognition: Data
    var previousIdentification: Data
    var correctedIdentification: Data
    @Attribute(.externalStorage) var scanJPEG: Data

    init(item: CollectionItem, previous: FeedbackIdentification, baseURL: String) throws {
        id = UUID()
        createdAt = Date()
        self.baseURL = baseURL
        originalRecognition = item.originalRecognition ?? Data()
        previousIdentification = try JSONEncoder().encode(previous)
        correctedIdentification = try JSONEncoder().encode(FeedbackIdentification(item))
        scanJPEG = item.resultScanJPEG ?? Data()
    }

    func payload() throws -> RecognitionFeedbackPayload {
        let decoder = JSONDecoder()
        return try RecognitionFeedbackPayload(
            eventID: id, createdAt: ISO8601DateFormatter().string(from: createdAt),
            originalRecognition: decoder.decode(RecognizedCard.self, from: originalRecognition),
            previousIdentification: decoder.decode(FeedbackIdentification.self, from: previousIdentification),
            correctedIdentification: decoder.decode(FeedbackIdentification.self, from: correctedIdentification),
            scanJPEG: scanJPEG
        )
    }

    @MainActor
    static func capture(item: CollectionItem, previous: FeedbackIdentification,
                        context: ModelContext, baseURL: String) throws {
        guard item.collection == nil, item.deck == nil, item.resultScanImage != nil,
              let original = item.originalRecognition,
              (try? JSONDecoder().decode(RecognizedCard.self, from: original)) != nil,
              previous != FeedbackIdentification(item) else { return }
        context.insert(try RecognitionFeedbackEvent(item: item, previous: previous, baseURL: baseURL))
    }
}
