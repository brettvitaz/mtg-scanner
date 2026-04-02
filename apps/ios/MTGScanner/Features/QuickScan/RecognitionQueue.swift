import Foundation
import SwiftData
import UIKit

/// Manages asynchronous card recognition jobs for Quick Scan mode.
///
/// Accepts captured images, dispatches them to the recognition API up to `maxConcurrent`
/// at a time, persists each result to SwiftData, and publishes running counts for the UI.
///
/// Retries each job once on failure before marking it failed.
@MainActor
final class RecognitionQueue: ObservableObject {

    // MARK: - Published State

    @Published private(set) var pendingCount = 0
    @Published private(set) var completedCount = 0
    @Published private(set) var failedCount = 0

    // MARK: - Configuration

    var maxConcurrent: Int = 2

    // MARK: - Private

    typealias RecognizeFunction = @Sendable (Data, String, String, String) async throws -> RecognitionResult

    private let recognize: RecognizeFunction
    private var activeCount = 0
    private var pendingJobs: [Job] = []

    private struct Job {
        let image: UIImage
        let filename: String
        let apiBaseURL: String
        let modelContext: ModelContext?
        var retryCount: Int = 0
    }

    // MARK: - Init

    init(recognize: @escaping RecognizeFunction = { data, filename, contentType, baseURL in
        try await APIClient().recognizeImage(
            data: data, filename: filename, contentType: contentType, baseURL: baseURL
        )
    }) {
        self.recognize = recognize
    }

    // MARK: - Public API

    func enqueue(image: UIImage, apiBaseURL: String, modelContext: ModelContext?) {
        let filename = "quickscan-\(UUID().uuidString.prefix(8)).jpg"
        pendingJobs.append(Job(image: image, filename: filename, apiBaseURL: apiBaseURL, modelContext: modelContext))
        pendingCount += 1
        drainIfPossible()
    }

    // MARK: - Private Queue Management

    private func drainIfPossible() {
        while activeCount < maxConcurrent, !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            activeCount += 1
            Task { await process(job: job) }
        }
    }

    private func process(job: Job) async {
        defer {
            activeCount -= 1
            drainIfPossible()
        }

        guard let jpeg = job.image.jpegData(compressionQuality: 0.9) else {
            pendingCount -= 1
            failedCount += 1
            return
        }

        do {
            let result = try await recognize(jpeg, job.filename, "image/jpeg", job.apiBaseURL)
            persist(result: result, modelContext: job.modelContext)
            pendingCount -= 1
            completedCount += 1
        } catch {
            if job.retryCount < 1 {
                var retried = job
                retried.retryCount += 1
                // Re-insert at front to retry before new work.
                pendingJobs.insert(retried, at: 0)
                activeCount -= 1
                drainIfPossible()
                activeCount += 1
            } else {
                pendingCount -= 1
                failedCount += 1
            }
        }
    }

    private func persist(result: RecognitionResult, modelContext: ModelContext?) {
        guard let modelContext else { return }
        for card in result.cards {
            modelContext.insert(CollectionItem(from: card, correction: nil))
        }
    }
}
