import XCTest
@testable import MTGScannerKit

final class CardDetectionViewModelTests: XCTestCase {
    @MainActor
    func testGrantPublishesCameraPermissionForSessionRebuild() {
        let model = CardDetectionViewModel()
        XCTAssertFalse(model.cameraPermissionGranted)
        model.updateCameraPermission(granted: true)
        XCTAssertTrue(model.cameraPermissionGranted)
        XCTAssertFalse(model.cameraPermissionDenied)
    }

    @MainActor
    func testDenialAndRegrantUpdateCameraLifecycleState() {
        let model = CardDetectionViewModel()
        model.updateCameraPermission(granted: true)
        model.updateCameraPermission(granted: false)
        XCTAssertFalse(model.cameraPermissionGranted)
        XCTAssertTrue(model.cameraPermissionDenied)
        model.updateCameraPermission(granted: true)
        XCTAssertTrue(model.cameraPermissionGranted)
        XCTAssertFalse(model.cameraPermissionDenied)
    }
}
