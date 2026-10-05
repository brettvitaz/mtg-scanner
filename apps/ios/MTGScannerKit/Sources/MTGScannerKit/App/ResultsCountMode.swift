import Foundation

enum ResultsCountMode: String, CaseIterable {
    case session
    case allResults
    case off

    var displayName: String {
        switch self {
        case .session: "This Session"
        case .allResults: "All Results"
        case .off: "Off"
        }
    }

    func count(sessionCount: Int, resultQuantity: Int) -> Int {
        switch self {
        case .session: sessionCount
        case .allResults: resultQuantity
        case .off: 0
        }
    }

    func badge(sessionCount: Int, resultQuantity: Int) -> String? {
        let count = count(sessionCount: sessionCount, resultQuantity: resultQuantity)
        guard count > 0 else { return nil }
        return count > 999 ? "999+" : String(count)
    }

    func accessibilityValue(sessionCount: Int, resultQuantity: Int) -> String {
        let count = count(sessionCount: sessionCount, resultQuantity: resultQuantity)
        return switch self {
        case .session: "\(count) cards scanned this session"
        case .allResults: "\(count) cards in Results"
        case .off: "Scan count off"
        }
    }
}
