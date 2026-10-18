import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class RootTabBadgeTests: XCTestCase {
    func testCaptureDestinationsAreIndependentNativeTabs() async throws {
        let app = AppModel()
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self, RecognitionFeedbackEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let library = LibraryViewModel()
        library.modelContext = context
        let root = RootTabView { mode, active in
            AnyView(ScanView(detectionMode: .constant(mode), isActive: active,
                             previewContent: { _ in AnyView(Color.black) }))
        }
        let window = makeScanCountWindow(view: root.environment(app)
            .environment(library).modelContainer(context.container))
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { self.findTabController(window.rootViewController)?.tabBar.items != nil }
        let controller = try XCTUnwrap(findTabController(window.rootViewController))
        XCTAssertEqual(controller.tabBar.items?.map(\.title), ["Table", "Station", "Results", "Library", "Settings"])
        XCTAssertEqual(controller.selectedIndex, 0)
        try await waitForScanCount { app.modelContext != nil }
        await app.retryRecognitionFeedback()
    }

    func testNativeResultsSelectionClearsBadgeAndSuppressesLateCards() async throws {
        let app = AppModel()
        app.selectTab(.settings)
        app.recordScannedCard()
        let context = try makeScanCountContext()
        let library = LibraryViewModel()
        library.modelContext = context
        app.modelContext = context
        let view = RootTabView().environment(app).environment(library).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        let tabBar = try await waitForBadge(in: window, badge: "1", accessibility: "1 newly scanned card")
        let controller = try XCTUnwrap(findTabController(window.rootViewController))
        let resultsController = try XCTUnwrap(controller.viewControllers?[AppTab.results.rawValue])
        // Deliver the callback UIKit sends after user selection to SwiftUI's binding coordinator.
        controller.selectedViewController = resultsController
        controller.delegate?.tabBarController?(controller, didSelect: resultsController)
        try await waitForScanCount { app.selectedTab == .results }
        XCTAssertEqual(app.selectedTab, .results)
        XCTAssertEqual(app.newlyScannedCardCount, 0)
        _ = try await waitForBadge(in: window, badge: nil, accessibility: "")
        XCTAssertNil(tabBar.items?[AppTab.results.rawValue].badgeValue)
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 0)
    }

    func testNativeBadgeExposesExactCountAndClearsOnProgrammaticNavigation() async throws {
        let app = AppModel()
        app.selectTab(.settings)
        for _ in 0..<1_000 { app.recordScannedCard() }
        let context = try makeScanCountContext()
        let library = LibraryViewModel()
        library.modelContext = context
        app.modelContext = context
        let view = RootTabView().environment(app).environment(library).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        let tabBar = try await waitForBadge(in: window, badge: "99+", accessibility: "1000 newly scanned cards")
        let item = try XCTUnwrap(tabBar.items?[AppTab.results.rawValue])
        XCTAssertEqual(item.badgeValue, "99+")
        XCTAssertEqual(item.accessibilityValue, "1000 newly scanned cards")

        app.shouldShowResults = true
        _ = try await waitForBadge(in: window, badge: nil, accessibility: "")
        XCTAssertEqual(app.selectedTab, .results)
        XCTAssertNil(item.badgeValue)
        XCTAssertEqual(item.accessibilityValue, "")
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 0)

        app.selectTab(.settings)
        app.recordScannedCard()
        _ = try await waitForBadge(in: window, badge: "1", accessibility: "1 newly scanned card")
        XCTAssertEqual(item.badgeValue, "1")
        XCTAssertEqual(item.accessibilityValue, "1 newly scanned card")
    }

    private func waitForBadge(in window: UIWindow, badge: String?, accessibility: String) async throws -> UITabBar {
        for _ in 0..<100 {
            if let tabBar = findTabBar(in: window), let items = tabBar.items,
               items.indices.contains(AppTab.results.rawValue) {
                let item = items[AppTab.results.rawValue]
                if item.badgeValue == badge, item.accessibilityValue == accessibility { return tabBar }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let items = findTabBar(in: window)?.items ?? []
        let index = AppTab.results.rawValue
        let item = items.indices.contains(index) ? items[index] : nil
        XCTFail("Badge did not settle: expected \(String(describing: badge))/\(accessibility), "
                + "actual \(String(describing: item?.badgeValue))/\(String(describing: item?.accessibilityValue))")
        throw URLError(.timedOut)
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
