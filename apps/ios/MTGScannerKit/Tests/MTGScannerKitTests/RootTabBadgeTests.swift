import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class RootTabBadgeTests: XCTestCase {
    func testNativeResultsSelectionClearsBadgeAndSuppressesLateCards() async throws {
        let app = AppModel()
        app.selectTab(3)
        app.recordScannedCard()
        let context = try makeScanCountContext()
        let library = LibraryViewModel()
        library.modelContext = context
        app.modelContext = context
        let view = RootTabView().environment(app).environment(library).modelContainer(context.container)
        let window = makeWindow(view: view)
        defer { closeScanCountWindow(window) }
        let tabBar = try await waitForBadge(in: window, badge: "1", accessibility: "1 newly scanned card")
        let controller = try XCTUnwrap(findTabController(window.rootViewController))
        let resultsController = try XCTUnwrap(controller.viewControllers?[1])
        // Deliver the callback UIKit sends after user selection to SwiftUI's binding coordinator.
        controller.selectedViewController = resultsController
        controller.delegate?.tabBarController?(controller, didSelect: resultsController)
        try await waitForScanCount { app.selectedTab == 1 }
        XCTAssertEqual(app.selectedTab, 1)
        XCTAssertEqual(app.newlyScannedCardCount, 0)
        _ = try await waitForBadge(in: window, badge: nil, accessibility: "")
        XCTAssertNil(tabBar.items?[1].badgeValue)
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 0)
    }

    func testNativeBadgeExposesExactCountAndClearsOnProgrammaticNavigation() async throws {
        let app = AppModel()
        app.selectTab(3)
        for _ in 0..<1_000 { app.recordScannedCard() }
        let context = try makeScanCountContext()
        let library = LibraryViewModel()
        library.modelContext = context
        app.modelContext = context
        let view = RootTabView().environment(app).environment(library).modelContainer(context.container)
        let window = makeWindow(view: view)
        defer { window.isHidden = true; window.rootViewController = nil }
        let tabBar = try await waitForBadge(in: window, badge: "99+", accessibility: "1000 newly scanned cards")
        let item = try XCTUnwrap(tabBar.items?[1])
        XCTAssertEqual(item.badgeValue, "99+")
        XCTAssertEqual(item.accessibilityValue, "1000 newly scanned cards")

        app.shouldShowResults = true
        _ = try await waitForBadge(in: window, badge: nil, accessibility: "")
        XCTAssertEqual(app.selectedTab, 1)
        XCTAssertNil(item.badgeValue)
        XCTAssertEqual(item.accessibilityValue, "")
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 0)

        app.selectTab(3)
        app.recordScannedCard()
        _ = try await waitForBadge(in: window, badge: "1", accessibility: "1 newly scanned card")
        XCTAssertEqual(item.badgeValue, "1")
        XCTAssertEqual(item.accessibilityValue, "1 newly scanned card")
    }

    private func makeWindow(view: some View) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        controller.view.layoutIfNeeded()
        return window
    }

    private func waitForBadge(in window: UIWindow, badge: String?, accessibility: String) async throws -> UITabBar {
        for _ in 0..<100 {
            if let tabBar = findTabBar(in: window), let items = tabBar.items, items.indices.contains(1),
               items[1].badgeValue == badge, items[1].accessibilityValue == accessibility { return tabBar }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(findTabBar(in: window))
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) { return tabBar }
        }
        return nil
    }

    private func findTabController(_ controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab }
        for child in controller.children {
            if let tab = findTabController(child) { return tab }
        }
        return nil
    }
}
