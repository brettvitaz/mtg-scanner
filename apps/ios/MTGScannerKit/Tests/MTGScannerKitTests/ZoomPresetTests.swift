import XCTest
@testable import MTGScannerKit

final class ZoomPresetTests: XCTestCase {
    func testAppliedZoomLabelKeepsFractionalValuesAndRoundsToOneDecimal() {
        XCTAssertEqual(ZoomPresetControl.label(1), "1×")
        XCTAssertEqual(ZoomPresetControl.label(1.5), "1.5×")
        XCTAssertEqual(ZoomPresetControl.label(1.73), "1.7×")
        XCTAssertEqual(ZoomPresetControl.label(2.4), "2.4×")
    }
}
