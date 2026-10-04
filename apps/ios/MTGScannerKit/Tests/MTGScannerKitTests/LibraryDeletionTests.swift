import SwiftData
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import MTGScannerKit

@MainActor
final class LibraryDeletionTests: XCTestCase {
    func testCollectionNamesRefreshAfterDeletingFirstMiddleAndLastRows() async throws {
        let container = try makeContainer()
        let collections = makeCollections(in: container.mainContext)
        let model = LibraryViewModel()
        model.modelContext = container.mainContext
        let window = showLibrary(container: container, model: model)
        defer { window.isHidden = true }

        try await assertNames(["Alpha", "Bravo", "Charlie", "Delta"], in: window)
        model.deleteCollections(at: IndexSet(integer: 0), from: collections)
        try await assertNames(["Bravo", "Charlie", "Delta"], absent: ["Alpha"], in: window)
        model.deleteCollections(at: IndexSet(integer: 1), from: Array(collections.dropFirst()))
        try await assertNames(["Bravo", "Delta"], absent: ["Alpha", "Charlie"], in: window)
        model.deleteCollections(at: IndexSet(integer: 1), from: [collections[1], collections[3]])
        try await assertNames(["Bravo"], absent: ["Alpha", "Charlie", "Delta"], in: window)
        model.renameCollection(collections[1], to: "Renamed")
        try await assertNames(["Renamed"], absent: ["Bravo"], in: window)
        model.deleteCollection(collections[1])
        try await assertNames(["No collections yet"], absent: ["Renamed"], in: window)
    }

    func testDeckNamesRefreshAfterDeletingFirstMiddleAndLastRows() async throws {
        let container = try makeContainer()
        let decks = makeDecks(in: container.mainContext)
        let model = LibraryViewModel()
        model.modelContext = container.mainContext
        let window = showLibrary(container: container, model: model)
        defer { window.isHidden = true }

        try await assertNames(["Alpha", "Bravo", "Charlie", "Delta"], in: window)
        model.deleteDecks(at: IndexSet(integer: 0), from: decks)
        try await assertNames(["Bravo", "Charlie", "Delta"], absent: ["Alpha"], in: window)
        model.deleteDecks(at: IndexSet(integer: 1), from: Array(decks.dropFirst()))
        try await assertNames(["Bravo", "Delta"], absent: ["Alpha", "Charlie"], in: window)
        model.deleteDecks(at: IndexSet(integer: 1), from: [decks[1], decks[3]])
        try await assertNames(["Bravo"], absent: ["Alpha", "Charlie", "Delta"], in: window)
        model.renameDeck(decks[1], to: "Renamed")
        try await assertNames(["Renamed"], absent: ["Bravo"], in: window)
        model.deleteDeck(decks[1])
        try await assertNames(["No decks yet"], absent: ["Renamed"], in: window)
    }

    func testDeletingFilteredCollectionOffsetsPreservesOtherCollectionsAndContents() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let collections = makeCollections(in: context)
        let card = CollectionItem(title: "Forest", edition: "Test", quantity: 3, collection: collections[1])
        context.insert(card)
        try context.save()
        let survivorID = collections[1].id
        let model = LibraryViewModel()
        model.modelContext = context

        model.deleteCollections(at: IndexSet([0, 2]), from: [collections[0], collections[2], collections[3]])
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CardCollection>())
        XCTAssertEqual(Set(remaining.map(\.id)), Set([survivorID, collections[2].id]))
        XCTAssertEqual(Set(remaining.map(\.name)), Set(["Bravo", "Charlie"]))
        let survivor = try XCTUnwrap(remaining.first { $0.id == survivorID })
        XCTAssertEqual(survivor.items.map(\.title), ["Forest"])
        XCTAssertEqual(survivor.items.totalQuantity, 3)
    }

    func testDeletingFilteredDeckOffsetsPreservesOtherDecksAndContents() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let decks = makeDecks(in: context)
        let card = CollectionItem(title: "Island", edition: "Test", quantity: 2, deck: decks[1])
        context.insert(card)
        try context.save()
        let survivorID = decks[1].id
        let model = LibraryViewModel()
        model.modelContext = context

        model.deleteDecks(at: IndexSet([0, 2]), from: [decks[0], decks[2], decks[3]])
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(Set(remaining.map(\.id)), Set([survivorID, decks[2].id]))
        XCTAssertEqual(Set(remaining.map(\.name)), Set(["Bravo", "Charlie"]))
        let survivor = try XCTUnwrap(remaining.first { $0.id == survivorID })
        XCTAssertEqual(survivor.items.map(\.title), ["Island"])
        XCTAssertEqual(survivor.items.totalQuantity, 2)
    }

    func testDeletingEmptyOffsetsLeavesCollectionsAndDecksUnchanged() throws {
        let container = try makeContainer()
        let collections = makeCollections(in: container.mainContext)
        let decks = makeDecks(in: container.mainContext)
        let model = LibraryViewModel()
        model.modelContext = container.mainContext

        model.deleteCollections(at: IndexSet(), from: collections)
        model.deleteDecks(at: IndexSet(), from: decks)

        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CardCollection>()), 4)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 4)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CardCollection.self, Deck.self, CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeCollections(in context: ModelContext) -> [CardCollection] {
        ["Alpha", "Bravo", "Charlie", "Delta"].enumerated().map { index, name in
            let collection = CardCollection(name: name)
            collection.updatedAt = Date(timeIntervalSince1970: 1_700_000_000 - Double(index))
            context.insert(collection)
            return collection
        }
    }

    private func makeDecks(in context: ModelContext) -> [Deck] {
        ["Alpha", "Bravo", "Charlie", "Delta"].enumerated().map { index, name in
            let deck = Deck(name: name)
            deck.updatedAt = Date(timeIntervalSince1970: 1_700_000_000 - Double(index))
            context.insert(deck)
            return deck
        }
    }

    private func showLibrary(container: ModelContainer, model: LibraryViewModel) -> UIWindow {
        let view = LibraryView().environment(model).modelContainer(container)
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        controller.view.frame = frame
        window.makeKeyAndVisible()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return window
    }

    private func assertNames(
        _ expected: [String], absent: [String] = [], in window: UIWindow,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await Task.sleep(for: .milliseconds(600))
        let view = try XCTUnwrap(window.rootViewController?.view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Library: \(expected.joined(separator: ", "))"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        for name in expected {
            XCTAssertEqual(labels.filter { $0 == name }.count, 1, "Rendered labels: \(labels)", file: file, line: line)
        }
        for name in absent {
            XCTAssertFalse(labels.contains(name), "Rendered labels: \(labels)", file: file, line: line)
        }
    }
}
