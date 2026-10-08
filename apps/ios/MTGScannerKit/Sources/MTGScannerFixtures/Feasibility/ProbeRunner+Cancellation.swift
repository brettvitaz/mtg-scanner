#if DEBUG
import Foundation

enum ProbeCancellation {
    static func catalog(source: URL, destination: URL) async throws {
        let worker = Task.detached {
            var rows = 0
            try ProbeCatalog.install(from: source, to: destination) {
                rows += 1
                if rows == 1000 { withUnsafeCurrentTask { $0?.cancel() } }
                try Task.checkCancellation()
            }
        }
        try await worker.value
    }
}

extension ProbeRunner {
    func cancelCatalog() async {
        let destination = root.appending(path: "catalog.sqlite")
        var evidence: [String: Any] = ["status": "Unverified"]
        do {
            let checksum = try ProbeDownload.digest(destination)
            do {
                try await ProbeCancellation.catalog(source: root.appending(path: "upstream.sqlite"),
                                                    destination: destination)
                throw ProbeError.invalidPayload
            } catch is CancellationError {
                try ProbeDownload.verify(destination, expected: checksum)
                evidence["status"] = "Pass"
                evidence["activeDatabaseUnchanged"] = true
                evidence["cancelledAfterCheckpoints"] = 1000
            }
        } catch { evidence["status"] = "Fail"; evidence["error"] = safeError(error) }
        record("cancelledCatalog", evidence)
    }
}
#endif
