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
    // swiftlint:disable:next line_length
    typealias RecognizeBatchFunction = @Sendable ([(data: Data, filename: String)], String, String) async throws -> RecognitionResult

    private let recognize: RecognizeFunction
    private let recognizeBatch: RecognizeBatchFunction
    private var activeCount = 0
    private var pendingJobs: [Job] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    private struct Job {
        let id: UUID = UUID()
        let image: UIImage
        let filename: String
        let apiBaseURL: String
        let modelContext: ModelContext?
        let isCropped: Bool
        let capturedAt: Date
        var retryCount: Int = 0
    }

    // MARK: - Init

    init(
        recognize: @escaping RecognizeFunction = { data, filename, contentType, baseURL in
            try await APIClient().recognizeImage(
                data: data, filename: filename, contentType: contentType, baseURL: baseURL
            )
        },
        recognizeBatch: @escaping RecognizeBatchFunction = { crops, contentType, baseURL in
            try await APIClient().recognizeBatch(crops: crops, contentType: contentType, baseURL: baseURL)
        }
    ) {
        self.recognize = recognize
        self.recognizeBatch = recognizeBatch
    }

    // MARK: - Public API

    func enqueue(image: UIImage, isCropped: Bool = false, apiBaseURL: String, modelContext: ModelContext?) {
        let filename = "scan-\(UUID().uuidString.prefix(8)).jpg"
        let job = Job(
            image: image, filename: filename, apiBaseURL: apiBaseURL,
            modelContext: modelContext, isCropped: isCropped, capturedAt: Date()
        )
        pendingJobs.append(job)
        pendingCount += 1
        drainIfPossible()
    }

    func cancelAll() {
        pendingJobs.removeAll()
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        pendingCount = 0
        activeCount = 0
    }

    // MARK: - Private Queue Management

    private func drainIfPossible() {
        while activeCount < maxConcurrent, !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            activeCount += 1
            let task = Task { await process(job: job) }
            activeTasks[job.id] = task
        }
    }

    private func process(job: Job) async {
        defer {
            activeTasks.removeValue(forKey: job.id)
            if !Task.isCancelled {
                activeCount -= 1
                drainIfPossible()
            }
        }

        guard !Task.isCancelled else { return }

        guard let jpeg = job.image.jpegData(compressionQuality: 0.9) else {
            pendingCount -= 1
            failedCount += 1
            return
        }

        do {
            let result = try await callAPI(jpeg: jpeg, job: job)
            guard !Task.isCancelled else { return }
            persist(result: result, modelContext: job.modelContext, capturedAt: job.capturedAt)
            pendingCount -= 1
            completedCount += 1
        } catch {
            guard !Task.isCancelled else { return }
            if job.retryCount < 1 {
                var retried = job
                retried.retryCount += 1
                // Re-insert at front to retry before new work.
                pendingJobs.insert(retried, at: 0)
            } else {
                pendingCount -= 1
                failedCount += 1
            }
        }
    }

    private func callAPI(jpeg: Data, job: Job) async throws -> RecognitionResult {
        if job.isCropped {
            return try await recognizeBatch(
                [(data: jpeg, filename: job.filename)],
                "image/jpeg",
                job.apiBaseURL
            )
        }
        return try await recognize(jpeg, job.filename, "image/jpeg", job.apiBaseURL)
    }

    private func persist(result: RecognitionResult, modelContext: ModelContext?, capturedAt: Date) {
        guard let modelContext else { return }
        for card in result.cards {
            let item = CollectionItem(from: card, correction: nil)
            item.addedAt = capturedAt
            modelContext.insert(item)
        }
    }
}
