import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class CameraControlConfigurationTests: XCTestCase {
    // A zoom-driven SwiftUI refresh must not enqueue repeated device configuration locks.
    func testUnchangedTorchAndExposureInputsDoNotRepeatHardwareWrites() async throws {
        var torchWrites: [Float] = []
        var exposureWrites: [Float] = []
        let camera = CameraViewController(configureTorch: { torchWrites.append($0) },
                                          configureExposure: { exposureWrites.append($0) }, startSession: { $0() })
        camera.loadViewIfNeeded()
        camera.viewDidAppear(false)
        defer { camera.shutDown() }
        try await waitForScanCount { torchWrites == [0] && exposureWrites == [0] }
        for _ in 0..<16 {
            camera.setTorchLevel(0)
            camera.setExposureBias(0)
        }
        XCTAssertEqual(torchWrites, [0])
        XCTAssertEqual(exposureWrites, [0])
        for _ in 0..<16 {
            camera.setTorchLevel(0.5)
            camera.setExposureBias(1)
        }
        XCTAssertEqual(torchWrites, [0, 0.5])
        XCTAssertEqual(exposureWrites, [0, 1])
    }
}
