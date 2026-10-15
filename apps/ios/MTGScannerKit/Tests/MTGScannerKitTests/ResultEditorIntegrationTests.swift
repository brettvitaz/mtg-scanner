import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ResultEditorIntegrationTests: XCTestCase {
    func testEditorCancelDiscardsChangedIdentificationWithoutCapture() async throws {
        let (context, item) = try fixture()
        let window = editor(item, context: context)
        defer { closeScanCountWindow(window) }
        let button = try await toolbarButton(in: window, saving: false)
        try activate(button)
        XCTAssertFalse(item.foil)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecognitionFeedbackEvent>()), 0)
    }

    func testEditorSaveWiresChangedIdentificationToExactlyOneCapture() async throws {
        let (context, item) = try fixture()
        let window = editor(item, context: context)
        defer { closeScanCountWindow(window) }
        let button = try await toolbarButton(in: window, saving: true)
        try activate(button)
        XCTAssertTrue(item.foil)
        let events = try context.fetch(FetchDescriptor<RecognitionFeedbackEvent>())
        XCTAssertEqual(events.count, 1)
        let payload = try XCTUnwrap(events.first).payload()
        XCTAssertFalse(payload.previousIdentification.foil)
        XCTAssertTrue(payload.correctedIdentification.foil)
        XCTAssertEqual(payload.originalRecognition.title, "Island")
    }

    private func editor(_ item: CollectionItem, context: ModelContext) -> UIWindow {
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.isFoil = true
        let view = EditCardView(draft: draft, scan: item.resultScanImage,
                               onSave: { $0.save(item: item, context: context, merge: $1) },
                               requiresMerge: { _ in false }).modelContainer(context.container)
        return makeScanCountWindow(view: view)
    }

    private func toolbarButton(in window: UIWindow, saving: Bool) async throws -> UIBarButtonItem {
        for _ in 0..<200 {
            if let item = navigationBar(in: window)?.topItem {
                let groups = saving ? item.trailingItemGroups : item.leadingItemGroups
                if let button = groups.flatMap(\.barButtonItems).first { return button }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("Editor controller: \(String(describing: window.rootViewController))")
        print(viewTree(window))
        throw NSError(domain: "Editor toolbar did not appear", code: 1)
    }

    private func viewTree(_ view: UIView, depth: Int = 0) -> String {
        guard depth < 10 else { return "" }
        let detail = (view as? UINavigationBar).map { " items=\(String(describing: $0.items))" } ?? ""
        let line = String(repeating: " ", count: depth) + String(describing: type(of: view)) + detail
        return ([line] + view.subviews.map { viewTree($0, depth: depth + 1) }).joined(separator: "\n")
    }

    private func navigationBar(in view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar { return bar }
        return view.subviews.compactMap { navigationBar(in: $0) }.first
    }

    private func activate(_ button: UIBarButtonItem) throws {
        let action = try XCTUnwrap(button.action, "Editor button must expose its native action")
        let target = try XCTUnwrap(button.target as? NSObject)
        XCTAssertTrue(target.responds(to: action))
        // Deliver the native target/action without requiring an app-hosted event loop.
        target.perform(action, with: button)
    }

    private func fixture() throws -> (ModelContext, CollectionItem) {
        let container = try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self,
                                          RecognitionFeedbackEvent.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
        }
        let card = RecognizedCard(title: "Island", edition: "Test", foil: false, confidence: 0.4,
                                  cropImageData: image.jpegData(compressionQuality: 1)?.base64EncodedString())
        let item = CollectionItem(from: card)
        item.attachResultEvidence(from: card)
        context.insert(item)
        try context.save()
        return (context, item)
    }
}
