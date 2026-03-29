import XCTest
@testable import MTGScanner

final class AppModelCropToggleTests: XCTestCase {

    private let storeKey = "on_device_crop_enabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storeKey)
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
}
