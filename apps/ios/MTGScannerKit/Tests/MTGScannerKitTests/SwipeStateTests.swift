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
}
