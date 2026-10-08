#if DEBUG
import Foundation
import UIKit

/// Only linked by the app's DEBUG import. Opt-in launch flag never persists in UserDefaults.
public enum FeasibilityProbe {
    @MainActor
    public static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--migration-probe") else { return }
        let original = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = original }
        let root = URL.documentsDirectory.appending(path: "phase1")
        await ProbeRunner(root: root).run()
    }
}

struct ProbeConfiguration: Codable, Sendable {
    struct Provider: Codable, Sendable {
        let kind: ProbeProvider.Kind
        let model: String
        let mode: ProbeProvider.Mode
    }
    let providers: [Provider]
    let samples: [String]
}

actor ProbeRunner {
    let root: URL
    private var report: [String: Any] = [:]
    let session = ProbeSessionDelegate.session()

    init(root: URL) { self.root = root }

    func run() async {
        defer { session.invalidateAndCancel() }
        report = ["startedAt": ISO8601DateFormatter().string(from: Date()),
                  "os": ProcessInfo.processInfo.operatingSystemVersionString,
                  "systemUptime": ProcessInfo.processInfo.systemUptime]
        #if targetEnvironment(simulator)
        report["environment"] = "simulator"
        #else
        report["environment"] = "physical-device"
        #endif
        do {
            let config = try JSONDecoder().decode(ProbeConfiguration.self, from: Data(
                contentsOf: root.appending(path: "config.json")))
            try save()
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--probe-catalog") { await catalog() }
            if args.contains("--probe-prices") { await prices() }
            if args.contains("--probe-recognition") { await recognition(config) }
            if args.contains("--probe-correction") { await correction(config) }
            if args.contains("--probe-cancel-catalog") { await cancelCatalog() }
            report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            report["memory"] = ProbeMetrics.memory()
            try save()
            print("PHASE1_FINISHED")
        } catch {
            report["runnerError"] = safeError(error)
            try? save()
            print("PHASE1_FAILED")
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appending(path: "report.json"), options: [.atomic, .completeFileProtection])
    }

    func record(_ name: String, _ value: [String: Any]) {
        report[name] = value
        do { try save() } catch { print("PHASE1_REPORT_WRITE_FAILED") }
        print("PHASE1_STEP \(name) \(value["status"] ?? "Unverified")")
    }

    func safeError(_ error: Error) -> String {
        if let error = error as? ProbeError { return error.localizedDescription }
        if error is CancellationError { return "Cancelled" }
        if let error = error as? URLError { return "URL error \(error.code.rawValue)" }
        return "Invalid input or storage error" // Never export upstream bodies, credentials or environment.
    }

    func fetch(_ source: String, filename: String) async throws -> URL {
        guard let url = URL(string: source), url.scheme == "https" else { throw ProbeError.invalidPayload }
        let destination = root.appending(path: filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try await ProbeDownload.fetch(url, to: destination, session: session)
        return destination
    }
}
#endif
