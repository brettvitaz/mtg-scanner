#if DEBUG
import Foundation

extension ProbeRunner {
    func catalog() async {
        let start = Date()
        var evidence: [String: Any] = ["status": "Unverified"]
        record("catalog", evidence)
        do {
            let base = "https://mtgjson.com/api/v5/AllPrintings.sqlite.gz"
            let checksum = try await fetch(base + ".sha256", filename: "catalog.sha256")
            let compressed = try await fetch(base, filename: "upstream.sqlite.gz")
            evidence["downloadSeconds"] = Date().timeIntervalSince(start)
            evidence["memoryAfterDownload"] = ProbeMetrics.memory()
            try ProbeDownload.verify(compressed, expected: String(contentsOf: checksum, encoding: .utf8))
            let importStart = Date()
            let upstream = root.appending(path: "upstream.sqlite")
            try ProbeDownload.decompress(compressed, to: upstream)
            evidence["memoryAfterDecompression"] = ProbeMetrics.memory()
            let destination = root.appending(path: "catalog.sqlite")
            var checkpoints = 0
            var peakDisk = ProbeMetrics.diskBytes(root)
            try ProbeCatalog.install(from: upstream, to: destination) {
                try Task.checkCancellation()
                checkpoints += 1
                if checkpoints.isMultiple(of: 1000) { peakDisk = max(peakDisk, ProbeMetrics.diskBytes(root)) }
            }
            evidence["importSeconds"] = Date().timeIntervalSince(importStart)
            peakDisk = max(peakDisk, ProbeMetrics.diskBytes(root))
            try catalogStatistics(destination, upstream: upstream, evidence: &evidence)
            evidence["peakDiskBytesAtCheckpoints"] = peakDisk
            let memory = ProbeMetrics.memory()
            evidence["memory"] = memory
            evidence["status"] = "Pass"
            if let seconds = evidence["importSeconds"] as? Double, let peak = memory["peakResidentBytes"] {
                evidence["performanceGate"] = seconds < 300 && peak < 250_000_000 ? "Pass" : "Fail"
            } else { evidence["performanceGate"] = "Unverified" }
        } catch { evidence["status"] = "Fail"; evidence["error"] = safeError(error) }
        record("catalog", evidence)
    }

    private func catalogStatistics(_ destination: URL, upstream: URL,
                                   evidence: inout [String: Any]) throws {
            let db = try ProbeSQLite(destination, readOnly: true)
            evidence["cardCount"] = try db.rows("SELECT COUNT(*) AS count FROM cards").first?["count"]
            evidence["setCount"] = try db.rows("SELECT COUNT(*) AS count FROM sets").first?["count"]
            evidence["faceCount"] = try db.rows("SELECT COUNT(*) AS count FROM face_names").first?["count"]
            evidence["sourceMeta"] = try ProbeSQLite(upstream, readOnly: true).rows("SELECT * FROM meta")
            evidence["samplePrintings"] = try db.rows("SELECT * FROM cards WHERE name IN "
                + "('Lightning Bolt','Fire // Ice','Wear // Tear','Plague Rats','Kruphix, God of Horizons')")
            evidence["sampleFaces"] = try db.rows(
                "SELECT * FROM face_names WHERE face_name IN ('Fire','Ice','Wear','Tear')")
    }

    func prices() async {
        let start = Date()
        var evidence: [String: Any] = ["status": "Unverified",
            "source": "https://www.cardkingdom.com/assets/json/product_catalog.json"]
        record("prices", evidence)
        do {
            let source = try await fetch("https://www.cardkingdom.com/assets/json/product_catalog.json",
                                         filename: "prices.json")
            evidence["downloadSeconds"] = Date().timeIntervalSince(start)
            let importStart = Date()
            let destination = root.appending(path: "prices.sqlite")
            try ProbePrices.install(from: source, to: destination)
            evidence["importSeconds"] = Date().timeIntervalSince(importStart)
            let db = try ProbeSQLite(destination, readOnly: true)
            evidence["priceCount"] = try db.rows("SELECT COUNT(*) AS count FROM ck_prices").first?["count"]
            evidence["samplePrices"] = try db.rows("SELECT * FROM ck_prices WHERE normalized_name IN "
                + "('lightning bolt','wear // tear','plague rats') ORDER BY normalized_name,id LIMIT 30")
            evidence["memory"] = ProbeMetrics.memory()
            evidence["status"] = "Pass"
        } catch { evidence["status"] = "Fail"; evidence["error"] = safeError(error) }
        record("prices", evidence)
    }
}
#endif
