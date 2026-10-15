import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

class FeedbackIntegrationTestCase: XCTestCase {
    private var savedDefaults: [String: Any] = [:]
    private let keys = ["api_base_url", "card_corrections"]

    override func setUp() {
        super.setUp()
        for key in keys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.set(savedDefaults[key], forKey: key) }
        super.tearDown()
    }
}

@MainActor
func feedbackFixture() throws -> (ModelContext, CollectionItem) {
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

@MainActor
func waitForFeedback(_ condition: () -> Bool) async throws {
    for _ in 0..<300 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Feedback integration condition did not settle")
    throw URLError(.timedOut)
}

@MainActor
func feedbackToolbarButton(in window: UIWindow, title: String) -> UIBarButtonItem? {
    func find(in view: UIView) -> UIBarButtonItem? {
        if let bar = view as? UINavigationBar, let item = bar.topItem {
            let isEditor = item.title == "Edit Card"
            if isEditor == (title != "Edit") {
                let groups = title == "Cancel" ? item.leadingItemGroups : item.trailingItemGroups
                if let button = groups.flatMap(\.barButtonItems).first { return button }
            }
        }
        return view.subviews.compactMap { find(in: $0) }.first
    }
    func find(in controller: UIViewController) -> UIBarButtonItem? {
        if let presented = controller.presentedViewController, let button = find(in: presented) { return button }
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        if let button = find(in: controller.view) { return button }
        return controller.children.compactMap { find(in: $0) }.first
    }
    return window.rootViewController.flatMap { find(in: $0) }
}

@MainActor
func activateFeedbackButton(_ button: UIBarButtonItem) throws {
    let action = try XCTUnwrap(button.action)
    let target = try XCTUnwrap(button.target as? NSObject)
    XCTAssertTrue(target.responds(to: action))
    target.perform(action, with: button)
}

@MainActor
@Observable
final class FeedbackRecorder {
    var attempts: [(RecognitionFeedbackPayload, String)] = []
    var acknowledge = false
    var fail = false

    func upload(_ payload: RecognitionFeedbackPayload, baseURL: String) async throws -> UUID {
        attempts.append((payload, baseURL))
        if fail { throw URLError(.notConnectedToInternet) }
        try await waitForFeedback { self.acknowledge }
        return payload.eventID
    }

    func app() -> AppModel {
        let app = AppModel(feedbackUploader: RecognitionFeedbackUploader(upload: { [self] payload, baseURL in
            try await upload(payload, baseURL: baseURL)
        }))
        // Price refreshes reject this unsupported transport locally, without network access.
        app.apiBaseURL = "feedback-test://configured"
        return app
    }
}

@MainActor
func feedbackViews(in root: UIView) -> [UIView] {
    [root] + root.subviews.flatMap(feedbackViews)
}
