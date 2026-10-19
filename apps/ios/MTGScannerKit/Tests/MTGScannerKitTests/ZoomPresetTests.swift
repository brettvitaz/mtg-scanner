import SwiftUI
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class ZoomPresetTests: XCTestCase {
    func testAppliedZoomLabelKeepsFractionalValuesAndRoundsToOneDecimal() {
        XCTAssertEqual(ZoomPresetControl.label(1), "1×")
        XCTAssertEqual(ZoomPresetControl.label(1.5), "1.5×")
        XCTAssertEqual(ZoomPresetControl.label(1.73), "1.7×")
        XCTAssertEqual(ZoomPresetControl.label(2.4), "2.4×")
    }

    func testFamilyUsesUnroundedAppliedValueAndKeepsUpperPinchRange() {
        for (value, family) in [(1.0, 1), (1.9999, 1), (2.0, 2), (2.9999, 2), (3.0, 3), (5.0, 3)] {
            XCTAssertEqual(ZoomPresetControl.family(value), family)
        }
        XCTAssertEqual(ZoomPresetControl.label(1.9999), "1.9×")
        XCTAssertEqual(ZoomPresetControl.label(2.9999), "2.9×")
    }

    func testEveryAnchorExposesNamedBaseAndHalfStepActions() throws {
        for family in 1...3 {
            var requested: CGFloat = 0
            let view = ZoomPresetControl(currentZoom: 1.9) { requested = $0 }
            let button = try view.inspect().findAll(ViewType.Button.self)[family - 1]
            do {
                try button.callAccessibilityAction("Select \(family)×")
            } catch where String(describing: error).contains("unavailable for inspection") {
                throw XCTSkip("ViewInspector cannot invoke SwiftUI named actions on this iOS runtime: \(error)")
            }
            XCTAssertEqual(requested, CGFloat(family))
            try button.callAccessibilityAction("Select \(family).5×")
            XCTAssertEqual(requested, CGFloat(family) + 0.5)
            try button.callAccessibilityAdjustableAction(.increment)
            XCTAssertEqual(requested, 2, accuracy: 0.001)
        }
    }

    // Keeping a menu or losing a base/half-step toggle must fail the production-control test.
    func testInlineAnchorsSelectBasesAndCycleEveryHalfStep() throws {
        for (value, anchor, expected) in [(1.0, 1, 1.5), (1.5, 1, 1.0), (1.9, 1, 1.0), (1.00001, 1, 1.0),
                                          (1.0, 2, 2.0), (2.0, 2, 2.5), (2.5, 2, 2.0),
                                          (2.1, 2, 2.0), (1.5, 3, 3.0), (3.0, 3, 3.5),
                                          (3.5, 3, 3.0), (4.0, 3, 3.0)] {
            var selected: CGFloat?
            let control = ZoomPresetControl(currentZoom: value) { selected = $0 }
            let buttons = try control.inspect().findAll(ViewType.Button.self)
            XCTAssertEqual(buttons.count, 3)
            guard buttons.count == 3 else { return }
            try buttons[anchor - 1].tap()
            XCTAssertEqual(try XCTUnwrap(selected), expected, accuracy: 0.001)
        }
    }
}
