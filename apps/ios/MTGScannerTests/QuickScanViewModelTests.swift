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

    func testNewSignalWhileSettlingDoesNotRestartTimer() async throws {
        // After the first signal starts the settle timer, additional signals while in
        // .settling must be ignored so the timer can actually complete.
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 60
        vm.start()

        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.captureState, .settling)

        // Subsequent signals should be ignored — state stays .settling.
        vm.presenceTracker.onNewCardSignal?(nil)
        vm.presenceTracker.onNewCardSignal?(nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.captureState, .settling)
    }

    func testSettleTimerCompletesWhenSignalsAreNotResent() async throws {
        // Verifies the core behaviour: settle timer must run to completion when
        // subsequent signals are ignored (the fix for the "always settling" bug).
        let vm = QuickScanViewModel(detector: nil)
        vm.captureDelay = 0.1  // short timer for the test
        vm.start()

        vm.presenceTracker.onNewCardSignal?(nil)
        // Keep firing signals — they must NOT reset the timer.
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(20))
            vm.presenceTracker.onNewCardSignal?(nil)
        }

        // Allow the 0.1 s timer to expire (plus a small buffer).
        try await Task.sleep(for: .milliseconds(200))

        // captureCoordinator is nil in this test, so triggerCapture returns early
        // but the state must have advanced past .settling.
        XCTAssertNotEqual(vm.captureState, .settling)
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
