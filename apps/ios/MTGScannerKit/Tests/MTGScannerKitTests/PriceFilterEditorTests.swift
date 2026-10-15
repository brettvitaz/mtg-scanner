import XCTest
@testable import MTGScannerKit

@MainActor
final class PriceFilterEditorTests: XCTestCase {
    func testCommitFormatsLocalizedDecimalsIntegersAndClearsEveryBound() throws {
        for (locale, input, formatted) in [("en_US", ".50", "0.50"), ("de_DE", ",50", "0,50"),
                                           ("fr_FR", "12,5", "12,50"), ("en_US", "12", "12.00")] {
            let state = CardFilterState()
            let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: locale))
            for field in PriceFilterEditor.Field.allCases {
                editor.drafts[field] = input
                XCTAssertTrue(editor.commit(field))
                XCTAssertEqual(editor.drafts[field], formatted)
                XCTAssertEqual(try XCTUnwrap(state[keyPath: field.bound]),
                               locale == "fr_FR" ? 12.5 : input == "12" ? 12 : 0.5, accuracy: 0.001)
                editor.drafts[field] = ""
                XCTAssertTrue(editor.commit(field))
                XCTAssertNil(state[keyPath: field.bound])
            }
        }
    }

    func testMalformedCompletionPreservesDraftAndLastValidBound() {
        let state = CardFilterState()
        state.priceRetailMin = 7
        let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: "en_US"))
        for input in [".", "1.2.3", "12oops", "words", "NaN", "∞"] {
            editor.drafts[.minRetail] = input
            XCTAssertFalse(editor.commit(.minRetail), input)
            XCTAssertEqual(editor.drafts[.minRetail], input)
            XCTAssertEqual(state.priceRetailMin, 7)
            XCTAssertNotNil(editor.errors[.minRetail])
        }
        editor.drafts[.minRetail] = "8.5"
        XCTAssertTrue(editor.commit(.minRetail))
        XCTAssertNil(editor.errors[.minRetail])
        XCTAssertEqual(state.priceRetailMin, 8.5)
    }

    func testRepeatedLocalizedSeparatorCannotCommit() {
        let state = CardFilterState()
        let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: "de_DE"))
        editor.drafts[.maxBuylist] = "1,2,3"
        XCTAssertFalse(editor.commit(.maxBuylist))
        XCTAssertNil(state.priceBuyMax)
    }

    func testNavigationCommitsInOrderAndDisablesBoundaryArrows() {
        let state = CardFilterState()
        let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(editor.move(to: .minRetail))
        XCTAssertFalse(editor.canMovePrevious)
        XCTAssertTrue(editor.canMoveNext)
        editor.drafts[.minRetail] = ".50"
        editor.next()
        XCTAssertEqual(editor.focusedField, .maxRetail)
        XCTAssertEqual(state.priceRetailMin, 0.5)
        editor.next()
        XCTAssertEqual(editor.focusedField, .minBuylist)
        editor.next()
        XCTAssertEqual(editor.focusedField, .maxBuylist)
        XCTAssertFalse(editor.canMoveNext)
        editor.previous()
        XCTAssertEqual(editor.focusedField, .minBuylist)
    }

    func testInvalidEntryBlocksNavigationReturnAndCompletion() {
        let state = CardFilterState()
        let editor = PriceFilterEditor(filterState: state)
        XCTAssertTrue(editor.move(to: .maxRetail))
        editor.drafts[.maxRetail] = "1.2.3"
        editor.previous()
        XCTAssertEqual(editor.focusedField, .maxRetail)
        editor.next()
        XCTAssertEqual(editor.focusedField, .maxRetail)
        editor.submit()
        XCTAssertEqual(editor.focusedField, .maxRetail)
        XCTAssertFalse(editor.move(to: nil))
        XCTAssertFalse(editor.finish())
        XCTAssertEqual(editor.focusedField, .maxRetail)
    }

    func testReturnAdvancesAndCompletesLastField() {
        let state = CardFilterState()
        let editor = PriceFilterEditor(filterState: state)
        XCTAssertTrue(editor.move(to: .minRetail))
        editor.submit()
        XCTAssertEqual(editor.focusedField, .maxRetail)
        XCTAssertTrue(editor.move(to: .maxBuylist))
        editor.drafts[.maxBuylist] = "5"
        editor.submit()
        XCTAssertNil(editor.focusedField)
        XCTAssertEqual(state.priceBuyMax, 5)
    }

    func testSheetDoneValidatesAllPendingEntriesAndReloadsCommittedValues() {
        let state = CardFilterState()
        let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: "en_US"))
        editor.drafts[.minRetail] = "3"
        editor.drafts[.minBuylist] = "bad"
        XCTAssertFalse(editor.finish())
        XCTAssertEqual(editor.focusedField, .minBuylist)
        XCTAssertNotNil(editor.errors[.minBuylist])
        editor.drafts[.minBuylist] = "1.5"
        XCTAssertTrue(editor.finish())
        XCTAssertNil(editor.focusedField)
        let reopened = PriceFilterEditor(filterState: state, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(reopened.drafts[.minRetail], "3.00")
        XCTAssertEqual(reopened.drafts[.minBuylist], "1.50")
        XCTAssertEqual(reopened.drafts[.maxRetail], "")
    }

    func testResetClearsDraftsErrorsNumericBoundsAndOtherFilters() {
        let state = CardFilterState()
        state.foilOnly = true
        state.priceRetailMin = 5
        let editor = PriceFilterEditor(filterState: state)
        editor.drafts[.maxBuylist] = "bad"
        XCTAssertFalse(editor.finish())
        XCTAssertTrue(editor.canReset)
        editor.reset()
        XCTAssertTrue(editor.errors.isEmpty)
        XCTAssertTrue(editor.drafts.values.allSatisfy(\.isEmpty))
        XCTAssertFalse(state.isActive)
        XCTAssertNil(editor.focusedField)
        XCTAssertFalse(editor.canReset)
        editor.drafts[.minRetail] = "."
        XCTAssertTrue(editor.canReset, "Reset must remain available for uncommitted drafts")
    }
}
