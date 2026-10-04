import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

final class SwipeStateTests: XCTestCase {
    private let rowWidth: CGFloat = 390

    func test_directionClassification() {
        XCTAssertEqual(SwipeState.direction(for: 0), .none)
        XCTAssertEqual(SwipeState.direction(for: 0.4), .none)
        XCTAssertEqual(SwipeState.direction(for: 2), .leading)
        XCTAssertEqual(SwipeState.direction(for: -2), .trailing)
    }

    func test_hasCrossedCommit() {
        XCTAssertFalse(SwipeState.hasCrossedCommit(offset: -100, rowWidth: rowWidth))
        XCTAssertTrue(SwipeState.hasCrossedCommit(offset: -250, rowWidth: rowWidth))
        XCTAssertTrue(SwipeState.hasCrossedCommit(offset: 250, rowWidth: rowWidth))
    }

    func test_resolveClosesWhenBelowOpenThreshold() {
        XCTAssertEqual(
            SwipeState.resolve(offset: -40, rowWidth: rowWidth, velocity: 0),
            .close
        )
        XCTAssertEqual(
            SwipeState.resolve(offset: 40, rowWidth: rowWidth, velocity: 0),
            .close
        )
    }

    func test_resolveOpensAtOpenThreshold() {
        XCTAssertEqual(
            SwipeState.resolve(offset: -90, rowWidth: rowWidth, velocity: 0),
            .open(.trailing)
        )
        XCTAssertEqual(
            SwipeState.resolve(offset: 90, rowWidth: rowWidth, velocity: 0),
            .open(.leading)
        )
    }

    func test_resolveCommitsPastCommitThreshold() {
        XCTAssertEqual(
            SwipeState.resolve(offset: -250, rowWidth: rowWidth, velocity: 0),
            .commit(.trailing)
        )
        XCTAssertEqual(
            SwipeState.resolve(offset: 250, rowWidth: rowWidth, velocity: 0),
            .commit(.leading)
        )
    }

    func test_flingCommitsPastOpenThresholdWhenVelocityDirectionMatches() {
        XCTAssertEqual(
            SwipeState.resolve(offset: -100, rowWidth: rowWidth, velocity: -1500),
            .commit(.trailing)
        )
        XCTAssertEqual(
            SwipeState.resolve(offset: 100, rowWidth: rowWidth, velocity: 1500),
            .commit(.leading)
        )
    }

    func test_flingInOppositeDirectionDoesNotCommit() {
        XCTAssertEqual(
            SwipeState.resolve(offset: -100, rowWidth: rowWidth, velocity: 1500),
            .open(.trailing)
        )
    }

    func test_commitThresholdHasMinimumAboveOpenThreshold() {
        XCTAssertGreaterThan(
            SwipeState.commitThreshold(rowWidth: 10),
            SwipeState.openDistance
        )
    }

    @MainActor
    func testRestoredRowClearsCachedSwipePresentation() async throws {
        let item = CollectionItem(title: "Restored Lightning Bolt", edition: "M10", quantity: 3)
        for offset: CGFloat in [-80, -390] {
            let row = CollectionItemRow(
                item: item, onSwipeDelete: {},
                swipeOffset: offset, rowWidth: 390, gestureBaseOffset: offset, crossedCommit: true
            )
            let image = try await render(row)
            let attachment = XCTAttachment(image: image)
            attachment.name = "restored-row-\(Int(offset))"
            attachment.lifetime = .keepAlways
            add(attachment)
            let pixels = try pixelCounts(image)
            XCTAssertLessThan(pixels.red, pixels.total / 1000,
                              "A restored row must not retain its red swipe-delete background.")
            XCTAssertGreaterThan(pixels.dark, pixels.total / 1000,
                                 "The card content must be visible, rather than shifted offscreen.")
        }
    }

    @MainActor
    private func render(_ row: CollectionItemRow) async throws -> UIImage {
        let controller = UIHostingController(rootView: row.frame(width: 390, height: 140))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 140))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { renderer in
            controller.view.layer.render(in: renderer.cgContext)
        }
    }

    private struct PixelCounts {
        let red: Int
        let dark: Int
        let total: Int
    }

    private func pixelCounts(_ image: UIImage) throws -> PixelCounts {
        let image = try XCTUnwrap(image.cgImage)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var red = 0
        var dark = 0
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            if data[offset] > 200, data[offset + 1] < 100, data[offset + 2] < 100 { red += 1 }
            if data[offset] < 100, data[offset + 1] < 100, data[offset + 2] < 100 { dark += 1 }
        }
        return PixelCounts(red: red, dark: dark, total: image.width * image.height)
    }

}
