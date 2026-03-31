import XCTest
@testable import MTGScanner

@MainActor
final class QuickScanViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsInactive() {
        let vm = QuickScanViewModel(detector: nil)
        XCTAssertFalse(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
    }

    func testInitialStatusMessageContainsStart() {
        let vm = QuickScanViewModel(detector: nil)
        XCTAssertTrue(vm.statusMessage.lowercased().contains("start"))
    }

    // MARK: - Start / Stop

    func testStartActivatesViewModel() {
        let vm = QuickScanViewModel(detector: nil)
        vm.start()
        XCTAssertTrue(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
    }

    func testStopDeactivatesViewModel() {
        let vm = QuickScanViewModel(detector: nil)
        vm.start()
        vm.stop()
        XCTAssertFalse(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
    }

    func testStopFromInactiveIsIdempotent() {
        let vm = QuickScanViewModel(detector: nil)
        vm.stop()
        XCTAssertFalse(vm.isActive)
    }

    // MARK: - Settle Timer

    func testSettleTimerTransitionsStateToSettling() async throws {
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 60  // very long so we don't reach capturing in this test
        vm.start()

        // Simulate a new-card signal by calling the internal signal handler directly
        // via the presenceTracker callback.
        vm.presenceTracker.onNewCardSignal?(nil)

        // Give main loop time to process the async dispatch.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.captureState, .settling)
    }

    func testStopCancelsSettleTimer() async throws {
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 60
        vm.start()
        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.captureState, .settling)

        vm.stop()
        XCTAssertFalse(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
    }

    func testNewSignalWhileSettlingRestartsTimer() async throws {
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 60
        vm.start()

        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.captureState, .settling)

        // Fire again while settling — should stay settling (timer restarted).
        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.captureState, .settling)
    }

    func testSignalIgnoredWhenInactive() async throws {
        let vm = QuickScanViewModel(detector: nil)
        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertFalse(vm.isActive)
    }

    // MARK: - Configuration

    func testDefaultCaptureDelay() {
        let vm = QuickScanViewModel(detector: nil)
        XCTAssertEqual(vm.captureDelay, 2.0, accuracy: 0.001)
    }

    func testCaptureDelayIsSettable() {
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 3.5
        XCTAssertEqual(vm.captureDelay, 3.5, accuracy: 0.001)
    }
}
