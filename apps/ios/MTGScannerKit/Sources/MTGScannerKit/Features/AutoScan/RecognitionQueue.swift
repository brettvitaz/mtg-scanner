import Foundation
import SwiftData
import UIKit

/// Manages asynchronous card recognition jobs for Auto Scan mode.
///
/// Accepts captured images, dispatches them to the recognition API up to `maxConcurrent`
/// at a time, persists each result to SwiftData, and publishes running counts for the UI.
///
/// Retries each job once on failure before marking it failed.
@MainActor
@Observable
final class RecognitionQueue {

    // MARK: - Published State

    private(set) var pendingCount = 0
    private(set) var completedCount = 0
    private(set) var failedCount = 0

    // MARK: - Callbacks

    /// Called when a card is successfully identified. The callback receives each recognized card.
    var onCardIdentified: ((RecognizedCard) -> Void)?

    // MARK: - Configuration

    var maxConcurrent: Int = 2

    // MARK: - Private

    typealias RecognizeFunction = @Sendable (Data, String, String, String) async throws -> RecognitionResult
    typealias CroppedBatch = [(data: Data, filename: String)]
    typealias RecognizeBatchFunction = @Sendable (CroppedBatch, String, String) async throws -> RecognitionResult

    private let recognize: RecognizeFunction
    private let recognizeBatch: RecognizeBatchFunction
    private var activeCount = 0
    private var pendingJobs: [Job] = []
    private var failedJobs: [Job] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    private struct Job {
        let id: UUID = UUID()
        let payload: RecognitionImagePayload
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

    func enqueue(
        payload: RecognitionImagePayload,
        isCropped: Bool = false,
        apiBaseURL: String,
        modelContext: ModelContext?
    ) {
        let filename = "scan-\(UUID().uuidString.prefix(8)).\(payload.preferredFilenameExtension)"
        let job = Job(
            payload: payload, filename: filename, apiBaseURL: apiBaseURL,
            modelContext: modelContext, isCropped: isCropped, capturedAt: Date()
        )
        pendingJobs.append(job)
        pendingCount += 1
        drainIfPossible()
    }

    func enqueue(image: UIImage, isCropped: Bool = false, apiBaseURL: String, modelContext: ModelContext?) {
        guard let payload = RecognitionImagePayload.generatedJPEG(from: image) else {
            failedCount += 1
            return
        }
        enqueue(payload: payload, isCropped: isCropped, apiBaseURL: apiBaseURL, modelContext: modelContext)
    }

    func cancelAll() {
        pendingJobs.removeAll()
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        pendingCount = 0
        // activeCount decrements naturally as cancelled tasks run their defer blocks.
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
            activeCount -= 1
            if !Task.isCancelled {
                drainIfPossible()
            }
        }

        guard !Task.isCancelled else { return }

        let uploadData = job.payload.uploadData
        let contentType = job.payload.contentType
        guard !uploadData.isEmpty else {
            pendingCount -= 1
            failedJobs.append(job)
            failedCount += 1
            return
        }

        do {
            let result = try await callAPI(data: uploadData, contentType: contentType, job: job)
            guard !Task.isCancelled else { return }
            persist(result: result, modelContext: job.modelContext, capturedAt: job.capturedAt)
            pendingCount -= 1
            completedCount += 1
        } catch {
            guard !Task.isCancelled else { return }
            handleFailure(job: job)
        }
    }

    private func handleFailure(job: Job) {
        if job.retryCount < 1 {
            var retried = job
            retried.retryCount += 1
            // Re-insert at front to retry before new work.
            pendingJobs.insert(retried, at: 0)
        } else {
            pendingCount -= 1
            failedJobs.append(job)
            failedCount += 1
        }
    }

    func retryFailed() {
        let jobs = failedJobs
        failedJobs.removeAll()
        failedCount = 0
        for var job in jobs {
            job.retryCount = 0
            pendingJobs.append(job)
            pendingCount += 1
        }
        drainIfPossible()
    }

    func clearFailed() {
        failedJobs.removeAll()
        failedCount = 0
    }

    private func callAPI(data: Data, contentType: String, job: Job) async throws -> RecognitionResult {
        if job.isCropped {
            return try await recognizeBatch(
                [(data: data, filename: job.filename)],
                contentType,
                job.apiBaseURL
            )
        }
        return try await recognize(data, job.filename, contentType, job.apiBaseURL)
    }

    private func persist(result: RecognitionResult, modelContext: ModelContext?, capturedAt: Date) {
        guard let modelContext else { return }
        for card in result.cards {
            let item = CollectionItem(from: card, correction: nil)
            item.addedAt = capturedAt
            modelContext.insert(item)
            onCardIdentified?(card)
        }
    }
}
