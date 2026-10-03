import Foundation

@MainActor
@Observable
final class CSVImportViewModel {
    var rows: [CSVImportRow] = []
    var isLoading = false
    var errorMessage: String?
    var filename = ""
    var processedRows = 0
    private var cache: [String: [CardPrinting]] = [:]

    var skippedCount: Int { rows.filter(\.isSkipped).count }
    var totalQuantity: Int? {
        var total = 0
        for row in rows where !row.isSkipped {
            let sum = total.addingReportingOverflow(row.record?.quantity ?? 0)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }
    var canImport: Bool {
        !isLoading && (totalQuantity ?? 0) > 0 && rows.allSatisfy {
            $0.isSkipped || ($0.record != nil && $0.printing != nil)
        }
    }

    func load(url: URL, fetch: (String) async throws -> [CardPrinting]) async {
        filename = url.lastPathComponent
        errorMessage = nil
        rows = []
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await CSVImportService().read(url: url)
            try Task.checkCancellation()
            rows = loaded
            if rows.isEmpty { errorMessage = "The CSV has no card rows. Choose another file." }
            await resolve(fetch: fetch)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolve(fetch: (String) async throws -> [CardPrinting]) async {
        isLoading = true
        processedRows = 0
        defer { isLoading = false }
        for index in rows.indices {
            guard !Task.isCancelled else { return }
            if let record = rows[index].record, !rows[index].isSkipped, rows[index].printing == nil {
                await resolveRow(index, record: record, fetch: fetch)
            }
            processedRows += 1
        }
    }

    func choose(_ printing: CardPrinting, for rowID: Int) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }), let record = rows[index].record,
              CSVPrintingResolver().supportsFinish(record, printing: printing) else { return }
        rows[index].printing = printing
        rows[index].issue = nil
        rows[index].isSkipped = false
    }

    func toggleSkip(_ rowID: Int) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].isSkipped.toggle()
    }

    private func resolveRow(
        _ index: Int, record: CSVImportRecord, fetch: (String) async throws -> [CardPrinting]
    ) async {
        do {
            let key = record.title.lowercased()
            let printings: [CardPrinting]
            if let cached = cache[key] { printings = cached } else {
                printings = try await fetch(record.title)
                try Task.checkCancellation()
                cache[key] = printings
            }
            guard !Task.isCancelled else { return }
            rows[index].printing = CSVPrintingResolver().resolve(record, among: printings)
            rows[index].issue = rows[index].printing == nil
                ? "No unique matching printing. Choose a printing or skip this row." : nil
        } catch is CancellationError {
            return
        } catch {
            rows[index].issue = "Could not load card information. "
                + "Check the server connection in Settings, then reopen this import."
        }
    }
}
