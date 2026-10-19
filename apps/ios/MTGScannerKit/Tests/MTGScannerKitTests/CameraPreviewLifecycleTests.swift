import AVFoundation
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class CameraPreviewLifecycleTests: XCTestCase {
    // Loading another tab must not replace the displayed preview or resize it offscreen.
    func testModeHandoffReusesTheConnectedPreviewAndIgnoresOutgoingLayout() throws {
        let manager = CameraSessionManager()
        let table = CameraViewController(sessionManager: manager, startSession: { $0() })
        let station = CameraViewController(sessionManager: manager, startSession: { $0() })
        table.loadViewIfNeeded()
        table.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        table.viewWillAppear(false)
        table.viewDidLayoutSubviews()
        let preview = try XCTUnwrap(table.view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.first)
        station.loadViewIfNeeded()
        XCTAssertTrue(preview.superlayer === table.view.layer, "Preloading must not steal the live preview")
        station.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        station.viewWillAppear(false)
        station.viewDidLayoutSubviews()
        XCTAssertTrue(preview.superlayer === station.view.layer)
        table.viewDidLayoutSubviews()
        XCTAssertEqual(preview.frame.size, CGSize(width: 375, height: 667))
        table.viewWillAppear(false)
        XCTAssertTrue(preview.superlayer === table.view.layer)
        XCTAssertEqual(preview.frame.size, CGSize(width: 402, height: 874))
        table.shutDown()
        station.shutDown()
    }

    func testCaptureTabHandoffDoesNotStopAndRestartTheRunningSession() {
        let session = LifecycleCaptureSession()
        let manager = CameraSessionManager(session: session)
        manager.setCaptureVisible(true)
        let table = UUID()
        let station = UUID()
        manager.setFrameHandler(owner: table) { _ in }
        manager.start(owner: table, onStarted: {})
        manager.pauseForNavigation(owner: table)
        manager.setFrameHandler(owner: station) { _ in }
        manager.start(owner: station, onStarted: {})
        manager.sessionQueue.sync {
            XCTAssertEqual(session.starts, 1)
            XCTAssertEqual(session.stops, 0)
        }
        manager.setCaptureVisible(false)
        manager.sessionQueue.sync { XCTAssertEqual(session.stops, 1) }
    }
}

private final class LifecycleCaptureSession: AVCaptureSession, @unchecked Sendable {
    var starts = 0
    var stops = 0
    private var simulatedRunning = false
    override var isRunning: Bool { simulatedRunning }
    override func startRunning() { starts += 1; simulatedRunning = true }
    override func stopRunning() { stops += 1; simulatedRunning = false }
}
