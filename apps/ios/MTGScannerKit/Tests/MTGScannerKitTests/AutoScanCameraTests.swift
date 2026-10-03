import AVFoundation
import XCTest
@testable import MTGScannerKit

final class AutoScanCameraTests: XCTestCase {
    func testAutoScanAutomaticallyUsesCloseUpWhenCapable() {
        XCTAssertEqual(AutoScanCamera.automatic.preferredDeviceType(closeUpAvailable: true), .builtInUltraWideCamera)
    }

    func testAutoScanFallsBackToWideWithoutCloseUpCapability() {
        XCTAssertEqual(AutoScanCamera.automatic.preferredDeviceType(closeUpAvailable: false), .builtInWideAngleCamera)
    }

    func testNormalScanKeepsWideEvenWhenCloseUpIsAvailable() {
        XCTAssertEqual(AutoScanCamera.standard.preferredDeviceType(closeUpAvailable: true), .builtInWideAngleCamera)
    }

    @MainActor
    func testCoordinatorWithoutCameraReturnsUnavailable() async {
        let coordinator = CameraCaptureCoordinator()
        coordinator.focus(on: CGPoint(x: 0.2, y: 0.7))
        let result = await coordinator.captureFocusedPhoto(focusPoint: nil)
        guard case .failure(.unavailable) = result else { return XCTFail("Expected unavailable camera") }
    }
}
