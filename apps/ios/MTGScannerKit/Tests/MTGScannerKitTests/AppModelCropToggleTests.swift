import XCTest
@testable import MTGScannerKit

final class AppModelCropToggleTests: XCTestCase {

    private let storeKey = "on_device_crop_enabled"
    private let autoScanDelayKey = "auto_scan_capture_delay"
    private let autoScanConfidenceKey = "auto_scan_confidence_threshold"
    private let oldQuickScanDelayKey = "quick_scan_capture_delay"
    private let oldQuickScanConfidenceKey = "quick_scan_confidence_threshold"
    private let maxConcurrentUploadsKey = "max_concurrent_uploads"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: autoScanDelayKey)
        UserDefaults.standard.removeObject(forKey: autoScanConfidenceKey)
        UserDefaults.standard.removeObject(forKey: oldQuickScanDelayKey)
        UserDefaults.standard.removeObject(forKey: oldQuickScanConfidenceKey)
        UserDefaults.standard.removeObject(forKey: maxConcurrentUploadsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: autoScanDelayKey)
        UserDefaults.standard.removeObject(forKey: autoScanConfidenceKey)
        UserDefaults.standard.removeObject(forKey: oldQuickScanDelayKey)
        UserDefaults.standard.removeObject(forKey: oldQuickScanConfidenceKey)
        UserDefaults.standard.removeObject(forKey: maxConcurrentUploadsKey)
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
    func testAutoScanCaptureDelayClampsStoredValueIntoSupportedRange() {
        UserDefaults.standard.set(8.0, forKey: autoScanDelayKey)
        let model = AppModel()
        XCTAssertEqual(model.autoScanCaptureDelay, 5.0, accuracy: 0.001)
    }

    @MainActor
    func testAutoScanConfidenceClampsStoredValueIntoSupportedRange() {
        UserDefaults.standard.set(0.1, forKey: autoScanConfidenceKey)
        let model = AppModel()
        XCTAssertEqual(model.autoScanConfidenceThreshold, 0.3, accuracy: 0.001)
    }

    @MainActor
    func testOldQuickScanKeysAreIgnored() {
        UserDefaults.standard.set(5.0, forKey: oldQuickScanDelayKey)
        UserDefaults.standard.set(0.9, forKey: oldQuickScanConfidenceKey)
        let model = AppModel()
        XCTAssertEqual(model.autoScanCaptureDelay, 2.0, accuracy: 0.001)
        XCTAssertEqual(model.autoScanConfidenceThreshold, 0.5, accuracy: 0.001)
    }

    // MARK: - maxConcurrentUploads

    @MainActor
    func testMaxConcurrentUploadsDefaultIsTwoWhenKeyAbsent() {
        let model = AppModel()
        XCTAssertEqual(model.maxConcurrentUploads, 2)
    }

    @MainActor
    func testMaxConcurrentUploadsPersistsToUserDefaults() {
        let model = AppModel()
        model.maxConcurrentUploads = 4

        let stored = UserDefaults.standard.integer(forKey: maxConcurrentUploadsKey)
        XCTAssertEqual(stored, 4)
    }

    @MainActor
    func testMaxConcurrentUploadsLoadsPersistedValue() {
        UserDefaults.standard.set(5, forKey: maxConcurrentUploadsKey)
        let model = AppModel()
        XCTAssertEqual(model.maxConcurrentUploads, 5)
    }

    @MainActor
    func testMaxConcurrentUploadsClampsAboveMaxToSix() {
        UserDefaults.standard.set(10, forKey: maxConcurrentUploadsKey)
        let model = AppModel()
        XCTAssertEqual(model.maxConcurrentUploads, 6)
    }

    @MainActor
    func testMaxConcurrentUploadsClampsZeroToDefault() {
        // UserDefaults.integer(forKey:) returns 0 when key is absent; also tests explicit 0.
        UserDefaults.standard.set(0, forKey: maxConcurrentUploadsKey)
        let model = AppModel()
        XCTAssertEqual(model.maxConcurrentUploads, 2)
    }
}
