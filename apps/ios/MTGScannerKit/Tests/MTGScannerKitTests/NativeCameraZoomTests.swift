import SwiftUI
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class NativeCameraZoomTests: XCTestCase {
    func testPresetUsesTheNativeRampAndPinchCancelsItFromTheAppliedFactor() throws {
        let camera = CameraViewController()
        var physical: CGFloat = 1
        var rampDestination: CGFloat?
        var reportProgress: CameraZoomDevice.Progress?
        var finish: CameraZoomDevice.Completion?
        var cancellationCount = 0
        camera.zoomDevice = CameraZoomDevice(
            maximum: 4, currentFactor: { physical },
            ramp: { destination, authorize, progress, complete in
                XCTAssertTrue(authorize())
                rampDestination = destination
                reportProgress = progress
                finish = complete
            },
            cancel: { progress in cancellationCount += 1; progress(physical) },
            change: { factor, authorize, complete in
                guard authorize() else { return }
                physical = factor
                complete(true)
            }
        )
        camera.setZoom(3, animated: true)
        XCTAssertEqual(rampDestination, 3)
        physical = 1.8
        try XCTUnwrap(reportProgress)(1.8)
        XCTAssertEqual(camera.appliedZoom, 1.8)
        camera.beginPinch()
        XCTAssertGreaterThan(cancellationCount, 0)
        camera.applyPinch(scale: 1.1)
        camera.endPinch()
        XCTAssertEqual(physical, 1.98, accuracy: 0.001)
        try XCTUnwrap(reportProgress)(3)
        try XCTUnwrap(finish)(true)
        XCTAssertEqual(camera.appliedZoom, 1.98, accuracy: 0.001)
        XCTAssertFalse(camera.isZoomMoving)
    }

    func testNoOpChecksThePhysicalFactorRatherThanAStaleControllerCache() {
        let camera = CameraViewController()
        var physical: CGFloat = 1.5
        var shown: CGFloat = 1
        camera.zoomDevice = CameraZoomDevice(maximum: 4, currentFactor: { physical }, change: { factor, allow, done in
            guard allow() else { return }
            physical = factor
            done(true)
        })
        camera.onZoomFactorChanged = { shown = $0 }
        camera.setZoom(1)
        XCTAssertEqual(physical, 1)
        physical = 2.5
        camera.synchronizeZoom()
        XCTAssertEqual(shown, 2.5)
        camera.setZoom(2.5)
        XCTAssertEqual(shown, 2.5)
    }

    func testRootCaptureDestinationsShareTheSameCameraSession() throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        let library = LibraryViewModel()
        let session = CameraSessionManager()
        let root = RootTabView(cameraSession: session).environment(app)
            .environment(library).modelContainer(context.container)
        let first = try root.inspect().find(ScanView.self).actualView()
        XCTAssertEqual(first.detectionMode, .scan)
        app.selectTab(.station)
        let second = try root.inspect().find(ScanView.self).actualView()
        XCTAssertEqual(second.detectionMode, .auto)
        XCTAssertTrue(first.cameraSession === session)
        XCTAssertTrue(second.cameraSession === session)
    }

    func testNativeRampRateUsesPowersOfTwoPerSecondInBothDirections() {
        XCTAssertEqual(CameraZoomDevice.rampRate(from: 1, to: 2), 4, accuracy: 0.001)
        XCTAssertEqual(CameraZoomDevice.rampRate(from: 2, to: 1), 4, accuracy: 0.001)
        XCTAssertEqual(CameraZoomDevice.rampRate(from: 1, to: 1.5), 2.33985, accuracy: 0.001)
    }

    func testOutgoingCameraOwnerCannotStopOrClearTheIncomingModeSession() {
        let manager = CameraSessionManager()
        let outgoing = UUID()
        let incoming = UUID()
        manager.setFrameHandler(owner: outgoing) { _ in }
        manager.setFrameHandler(owner: incoming) { _ in }
        manager.sessionQueue.sync { manager.isSessionReady = true }
        manager.pauseForNavigation(owner: outgoing)
        manager.shutDown(owner: outgoing)
        manager.sessionQueue.sync {
            XCTAssertTrue(manager.isSessionReady)
            XCTAssertNotNil(manager.onFrame)
        }
        manager.pauseForNavigation(owner: incoming)
        manager.sessionQueue.sync { XCTAssertFalse(manager.isSessionReady) }
    }

}
