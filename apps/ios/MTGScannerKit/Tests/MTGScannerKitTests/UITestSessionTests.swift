#if DEBUG
import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class UITestSessionTests: XCTestCase {
    private let runID = UUID()

    func testFreshResetsSavedDataAndPreferences() throws {
        defer { try? UITestSession.cleanup(runID: runID) }
        try changeSavedFinish()
        let fresh = try UITestSession(runID: runID, mode: .fresh)
        let items = try fresh.container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Lightning Bolt")
        XCTAssertEqual(items.first?.foil, false)
        XCTAssertNil(fresh.preferences.string(forKey: "api_base_url"))
        XCTAssertTrue(fresh.appModel.corrections.isEmpty)
    }

    func testResumeRetainsSavedDataAndPreferences() throws {
        defer { try? UITestSession.cleanup(runID: runID) }
        let id = try changeSavedFinish()
        let resumed = try UITestSession(runID: runID, mode: .resume)
        let items = try resumed.container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, id)
        XCTAssertEqual(items.first?.foil, true)
        XCTAssertEqual(resumed.appModel.apiBaseURL, "https://retained.invalid")
        XCTAssertEqual(resumed.appModel.corrections[id]?.foil, true)
    }

    func testRunIdentifiersIsolateStoresPreferencesAndCleanup() throws {
        defer { try? UITestSession.cleanup(runID: runID) }
        let otherID = UUID()
        defer { try? UITestSession.cleanup(runID: otherID) }
        let originalID = try changeSavedFinish()
        let other = try UITestSession(runID: otherID, mode: .fresh)
        XCTAssertEqual(try other.container.mainContext.fetch(FetchDescriptor<CollectionItem>()).first?.foil, false)
        XCTAssertNotEqual(other.appModel.apiBaseURL, "https://retained.invalid")
        XCTAssertTrue(other.appModel.corrections.isEmpty)
        try UITestSession.cleanup(runID: otherID)
        XCTAssertThrowsError(try UITestSession(runID: otherID, mode: .resume))
        let resumed = try UITestSession(runID: runID, mode: .resume)
        let item = try XCTUnwrap(resumed.container.mainContext.fetch(FetchDescriptor<CollectionItem>()).first)
        XCTAssertEqual(item.id, originalID)
        XCTAssertTrue(item.foil)
        XCTAssertEqual(resumed.appModel.apiBaseURL, "https://retained.invalid")
    }

    func testResumeWithoutFreshStoreFailsInsteadOfSeeding() {
        XCTAssertThrowsError(try UITestSession(runID: runID, mode: .resume))
    }

    @discardableResult
    private func changeSavedFinish() throws -> UUID {
        let session = try UITestSession(runID: runID, mode: .fresh)
        let item = try XCTUnwrap(session.container.mainContext.fetch(FetchDescriptor<CollectionItem>()).first)
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.isFoil = true
        XCTAssertTrue(draft.save(item: item, context: session.container.mainContext, merge: false))
        session.appModel.apiBaseURL = "https://retained.invalid"
        session.appModel.saveCorrection(CardCorrection(from: item.toRecognizedCard()))
        return item.id
    }
}
#endif
