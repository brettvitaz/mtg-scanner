import SwiftUI
import XCTest

@testable import MTGScannerKit

final class RarityTests: XCTestCase {
    func testParsesLowercase() {
        XCTAssertEqual(Rarity("mythic"), .mythic)
        XCTAssertEqual(Rarity("rare"), .rare)
        XCTAssertEqual(Rarity("uncommon"), .uncommon)
        XCTAssertEqual(Rarity("common"), .common)
    }

    func testParsesUppercase() {
        XCTAssertEqual(Rarity("MYTHIC"), .mythic)
        XCTAssertEqual(Rarity("RARE"), .rare)
    }

    func testParsesWithWhitespace() {
        XCTAssertEqual(Rarity("  rare  "), .rare)
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(Rarity("special"))
        XCTAssertNil(Rarity(""))
        XCTAssertNil(Rarity(nil))
    }

    func testOverlayColorClearForCommon() {
        XCTAssertEqual(Rarity.common.overlayColor(for: .dark), .clear)
        XCTAssertEqual(Rarity.common.overlayColor(for: .light), .clear)
    }

    func testOverlayColorNonClearForOtherRarities() {
        for rarity in [Rarity.mythic, .rare, .uncommon] {
            XCTAssertNotEqual(rarity.overlayColor(for: .dark), .clear, "\(rarity) should have overlay")
            XCTAssertNotEqual(rarity.overlayColor(for: .light), .clear, "\(rarity) should have overlay")
        }
    }
}
