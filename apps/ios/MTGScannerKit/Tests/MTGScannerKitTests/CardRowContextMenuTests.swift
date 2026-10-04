import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardRowContextMenuTests: XCTestCase {
    func testUnavailableActionsDoNotCreateContextMenu() {
        let row = makeRow(actions: CardRowMenuActions())
        let coordinator = row.makeCoordinator()
        XCTAssertNil(coordinator.contextMenuInteraction(
            UIContextMenuInteraction(delegate: coordinator), configurationForMenuAtLocation: .zero
        ))
    }

    func testMenuGroupsActionsAndUsesCurrentFoilLabel() throws {
        let actions = CardRowMenuActions(transfer: {}, toggleFoil: {}, delete: {})
        let menu = actions.menu(isFoil: false)
        let primary = try XCTUnwrap(menu.children.first as? UIMenu)
        XCTAssertEqual(primary.children.map(\.title), ["Copy/Move", "Set as Foil"])
        let destructive = try XCTUnwrap(menu.children.last as? UIMenu)
        let delete = try XCTUnwrap(destructive.children.first as? UIAction)
        XCTAssertEqual(delete.title, "Delete")
        XCTAssertTrue(delete.attributes.contains(.destructive))
        let foilGroup = try XCTUnwrap(actions.menu(isFoil: true).children.first as? UIMenu)
        XCTAssertEqual(foilGroup.children.last?.title, "Set as Non-Foil")
        XCTAssertEqual(CardRowMenuActions(delete: {}).menu(isFoil: false).children.count, 1)
    }

    func testNativeActionsInvokeOnlyTheirMatchingCallback() throws {
        var calls: [String] = []
        let actions = CardRowMenuActions(
            transfer: { calls.append("transfer") }, toggleFoil: { calls.append("foil") },
            delete: { calls.append("delete") }, navigate: { calls.append("navigate") }
        )
        for group in actions.menu(isFoil: false).children {
            let menu = try XCTUnwrap(group as? UIMenu)
            for element in menu.children {
                let action = try XCTUnwrap(element as? UIAction)
                let button = UIButton(type: .system)
                button.addAction(action, for: .touchUpInside)
                button.sendActions(for: .touchUpInside)
            }
        }
        XCTAssertEqual(calls, ["transfer", "foil", "delete"])
    }

    func testPreviewDoesNotNavigateAndCommitNavigatesAfterCompletion() throws {
        var navigated = 0
        let row = makeRow(actions: CardRowMenuActions(transfer: {}, navigate: { navigated += 1 }))
        let coordinator = row.makeCoordinator()
        let interaction = UIContextMenuInteraction(delegate: coordinator)
        let configuration = try XCTUnwrap(coordinator.contextMenuInteraction(
            interaction, configurationForMenuAtLocation: .zero
        ))
        XCTAssertEqual(navigated, 0)
        let animator = CommitAnimator()
        coordinator.contextMenuInteraction(
            interaction, willPerformPreviewActionForMenuWith: configuration, animator: animator
        )
        XCTAssertEqual(navigated, 0)
        XCTAssertEqual(animator.completions.count, 1)
        animator.completions.forEach { $0() }
        XCTAssertEqual(navigated, 1)
    }

    func testPreviewFitsSmallLandscapeAndPhoneBounds() {
        let phone = CardRowPreview.size(in: CGSize(width: 390, height: 844))
        XCTAssertEqual(phone.width, 340)
        XCTAssertLessThanOrEqual(phone.height, 520)
        let landscape = CardRowPreview.size(in: CGSize(width: 320, height: 240))
        XCTAssertLessThan(landscape.width, 280)
        XCTAssertLessThan(landscape.height, 240)
    }

    func testPreviewPreservesCardRatioWithinAvailableBounds() {
        for bounds in [CGSize(width: 390, height: 844), CGSize(width: 320, height: 240)] {
            let size = CardRowPreview.size(in: bounds)
            XCTAssertEqual((size.width - 16) / (size.height - 16), 63.0 / 88.0, accuracy: 0.001)
            XCTAssertLessThanOrEqual(size.width, min(340, bounds.width - 40))
            XCTAssertLessThanOrEqual(size.height, min(520, bounds.height * 0.58))
        }
        let fallback = CardRowPreview.size(in: CGSize(width: 390, height: 844), hasArtwork: false)
        XCTAssertEqual(fallback.width, 340)
        XCTAssertLessThan(fallback.height, CardRowPreview.size(in: CGSize(width: 390, height: 844)).height)
        let empty = CardRowPreview.size(in: .zero)
        XCTAssertGreaterThan(empty.width, 0)
        XCTAssertGreaterThan(empty.height, 0)
    }

    func testPreviewAccessibleIdentityIncludesPrintingAndFinishWithoutPrices() {
        let item = CollectionItem(title: "Island", edition: "Foundations")
        item.setCode = "fdn"
        item.collectorNumber = "275"
        item.foil = true
        XCTAssertEqual(CardRowPreview(item: item).accessibilitySummary,
                       "Island, Foundations, FDN · #275, Foil")
        item.setCode = nil
        item.collectorNumber = nil
        item.foil = false
        XCTAssertEqual(CardRowPreview(item: item).accessibilitySummary,
                       "Island, Foundations, Non-Foil")
    }

    private func makeRow(
        actions: CardRowMenuActions
    ) -> CardRowContextMenu<Text> {
        CardRowContextMenu(
            content: Text("Card"), item: CollectionItem(title: "Island", edition: "Foundations"),
            actions: actions
        )
    }
}

@MainActor
private final class CommitAnimator: NSObject, UIContextMenuInteractionCommitAnimating {
    var previewViewController: UIViewController?
    var preferredCommitStyle: UIContextMenuInteractionCommitStyle = .dismiss
    var completions: [() -> Void] = []

    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
}
