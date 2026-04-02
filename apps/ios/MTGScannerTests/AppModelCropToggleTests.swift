import XCTest
@testable import MTGScanner

final class AppModelCropToggleTests: XCTestCase {

    private let storeKey = "on_device_crop_enabled"
    private let quickScanDelayKey = "quick_scan_capture_delay"
    private let quickScanConfidenceKey = "quick_scan_confidence_threshold"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: quickScanDelayKey)
        UserDefaults.standard.removeObject(forKey: quickScanConfidenceKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: quickScanDelayKey)
        UserDefaults.standard.removeObject(forKey: quickScanConfidenceKey)
        super.tearDown()
    }

    // MARK: - Default value

    @MainActor
    func testDefaultValueIsTrueWhenNoStoredValue() {
        let model = AppModel()
        XCTAssertTrue(model.onDeviceCropEnabled)
    }

    // MARK: - Persistence

    @MainActor
    func testSettingToFalsePersistsToUserDefaults() {
        let model = AppModel()
        model.onDeviceCropEnabled = false

        let stored = UserDefaults.standard.object(forKey: storeKey) as? Bool
        XCTAssertEqual(stored, false)
    }

    @MainActor
    func testSettingToTruePersistsToUserDefaults() {
        UserDefaults.standard.set(false, forKey: storeKey)
        let model = AppModel()
        model.onDeviceCropEnabled = true

        let stored = UserDefaults.standard.object(forKey: storeKey) as? Bool
        XCTAssertEqual(stored, true)
    }

    // MARK: - Loading

    @MainActor
    func testLoadsPersistedFalseValue() {
        UserDefaults.standard.set(false, forKey: storeKey)
        let model = AppModel()
        XCTAssertFalse(model.onDeviceCropEnabled)
    }

    @MainActor
    func testLoadsPersistedTrueValue() {
        UserDefaults.standard.set(true, forKey: storeKey)
        let model = AppModel()
        XCTAssertTrue(model.onDeviceCropEnabled)
    }

    @MainActor
    func testQuickScanCaptureDelayClampsStoredValueIntoSupportedRange() {
        UserDefaults.standard.set(8.0, forKey: quickScanDelayKey)
        let model = AppModel()
        XCTAssertEqual(model.quickScanCaptureDelay, 5.0, accuracy: 0.001)
    }

    @MainActor
    func testQuickScanConfidenceClampsStoredValueIntoSupportedRange() {
        UserDefaults.standard.set(0.1, forKey: quickScanConfidenceKey)
        let model = AppModel()
        XCTAssertEqual(model.quickScanConfidenceThreshold, 0.3, accuracy: 0.001)
    }
}
