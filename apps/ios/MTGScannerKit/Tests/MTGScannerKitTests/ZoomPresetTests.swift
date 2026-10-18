import SwiftUI
import UIKit
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

    func testZoomSurfaceFitsItsNativeButtonWithoutAnEmptyTrailingRegion() async throws {
        for zoom in [CGFloat(1), 1.7] {
            let measurement = ZoomLayoutMeasurement()
            let view = ZoomPresetControl(currentZoom: zoom) { _ in }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { measurement.size = geometry.size }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            let window = makeScanCountWindow(view: view)
            defer { closeScanCountWindow(window) }
            try await waitForScanCount { measurement.size.width > 0 }
            let button = try XCTUnwrap(zoomButton(in: window))
            XCTAssertEqual(measurement.size.width, button.bounds.width, accuracy: 1)
            XCTAssertEqual(button.bounds.width, button.intrinsicContentSize.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            let title = try XCTUnwrap(button.titleLabel)
            let icon = try XCTUnwrap(button.imageView)
            let leading = title.convert(title.bounds, to: button).minX
            let trailing = button.bounds.maxX - icon.convert(icon.bounds, to: button).maxX
            XCTAssertEqual(leading, trailing, accuracy: 2)
            XCTAssertLessThanOrEqual(trailing, 16)
        }
    }

    private func zoomButton(in root: UIView) -> UIButton? {
        var remaining = [root]
        while let view = remaining.popLast() {
            if let button = view as? UIButton, button.accessibilityIdentifier == "capture-zoom" { return button }
            remaining.append(contentsOf: view.subviews)
        }
        return nil
    }
}

@MainActor
private final class ZoomLayoutMeasurement { var size = CGSize.zero }
