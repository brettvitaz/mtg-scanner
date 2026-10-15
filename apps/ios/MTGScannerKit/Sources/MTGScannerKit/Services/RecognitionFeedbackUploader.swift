import Foundation
import SwiftData

@MainActor
final class RecognitionFeedbackUploader {
    typealias Upload = @Sendable (RecognitionFeedbackPayload, String) async throws -> UUID
    private let upload: Upload
    private var running = false
    private var retryRequested = false

    init(upload: @escaping Upload = { payload, baseURL in
        try await APIClient().uploadFeedback(payload, baseURL: baseURL)
    }) {
        self.upload = upload
    }

    func retry(context: ModelContext) async {
        guard !running else {
            retryRequested = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            retryRequested = false
            await drain(context: context)
        } while retryRequested && !Task.isCancelled
    }

    private func drain(context: ModelContext) async {
        do {
            let query = FetchDescriptor<RecognitionFeedbackEvent>(sortBy: [SortDescriptor(\.createdAt)])
            let events = try context.fetch(query)
            for event in events {
                guard !Task.isCancelled else { return }
                await send(event, context: context)
            }
        } catch {
            print("[Recognition feedback] Could not load outbox: \(error)")
        }
    }

    private func send(_ event: RecognitionFeedbackEvent, context: ModelContext) async {
        do {
            let acknowledgedID = try await upload(event.payload(), event.baseURL)
            guard acknowledgedID == event.id else { throw APIClient.APIError.invalidResponse }
            // Flush unrelated edits before deleting only the acknowledged event.
            try context.save()
            context.delete(event)
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        } catch {
            print("[Recognition feedback] Retaining \(event.id) for retry: \(error)")
        }
    }
}

extension APIClient {
    func uploadFeedback(_ payload: RecognitionFeedbackPayload, baseURL: String) async throws -> UUID {
        guard let base = URL(string: baseURL), base.scheme == "http" || base.scheme == "https" else {
            throw APIError.invalidBaseURL
        }
        var request = URLRequest(url: base.appending(path: "/api/v1/recognition-feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw APIError.invalidResponse
        }
        let acknowledgement = try JSONDecoder().decode(FeedbackAcknowledgement.self, from: data)
        guard acknowledgement.accepted else { throw APIError.invalidResponse }
        return acknowledgement.eventID
    }
}

private struct FeedbackAcknowledgement: Decodable {
    let eventID: UUID
    let accepted: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case accepted
    }
}
