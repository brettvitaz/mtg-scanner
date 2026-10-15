import SwiftUI
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class PriceFilterFieldTests: XCTestCase {
    private var diagnosticWindow: UIWindow?
    private var diagnosticEditor: PriceFilterEditor?
    func testFirstSeparatorRemainsVisibleWhileEditing() async throws {
        let (window, editor) = host()
        defer { close(window) }
        let field = try await priceField(.minRetail, in: window)
        field.becomeFirstResponder()
        try select(0..<0, in: field)
        field.insertText(".")
        notifyEdit(field)
        try await wait { editor.drafts[.minRetail] == "." }
        XCTAssertEqual(field.text, ".", "Numeric formatting must not consume the first separator")
    }

    func testAllFieldsPreserveMiddleReplacementPasteAndDeletion() async throws {
        let state = CardFilterState()
        for key in PriceFilterEditor.Field.allCases { state[keyPath: key.bound] = 12.5 }
        let (window, editor) = host(state: state)
        defer { close(window) }
        for key in PriceFilterEditor.Field.allCases {
            XCTAssertTrue(editor.move(to: key))
            let field = try await priceField(key, in: window)
            field.becomeFirstResponder()
            try select(1..<2, in: field)
            field.copy(nil)
            XCTAssertEqual(UIPasteboard.general.string, "2")
            field.insertText("9")
            notifyEdit(field)
            try await wait { editor.drafts[key] == "19.50" }
            XCTAssertEqual(field.text, "19.50")
            try select(2..<5, in: field)
            UIPasteboard.general.string = ".75"
            field.paste(nil)
            notifyEdit(field)
            try await wait { editor.drafts[key] == "19.75" }
            XCTAssertEqual(field.text, "19.75")
            try select(2..<2, in: field)
            field.deleteBackward()
            notifyEdit(field)
            try await wait { editor.drafts[key] == "1.75" }
            XCTAssertEqual(state[keyPath: key.bound], 12.5, "Typing must not update numeric bounds")
        }
    }

    func testTappingAnotherFieldCommitsAndInvalidEntryRestoresFocus() async throws {
        let (window, editor) = host()
        defer { close(window) }
        let first = try await priceField(.minRetail, in: window)
        first.becomeFirstResponder()
        first.insertText(".50")
        notifyEdit(first)
        try await wait { editor.drafts[.minRetail] == ".50" }
        let second = try await priceField(.maxRetail, in: window)
        second.becomeFirstResponder()
        try await wait { editor.focusedField == .maxRetail }
        XCTAssertEqual(editor.drafts[.minRetail], "0.50")
        second.insertText("1.2.3")
        notifyEdit(second)
        try await wait { editor.drafts[.maxRetail] == "1.2.3" }
        first.becomeFirstResponder()
        try await wait { second.isFirstResponder && editor.errors[.maxRetail] != nil }
        XCTAssertEqual(editor.focusedField, .maxRetail)
        XCTAssertEqual(second.text, "1.2.3")
    }

    private func host(state: CardFilterState = CardFilterState()) -> (UIWindow, PriceFilterEditor) {
        let editor = PriceFilterEditor(filterState: state, locale: Locale(identifier: "en_US"))
        editor.move(to: .minRetail)
        let sheet = FilterSheet(filterState: state, items: [
            CollectionItem(title: "Island", edition: "Test", priceRetail: "$1.00")
        ], priceEditor: editor)
        let window = makeWindow(view: sheet)
        diagnosticWindow = window
        diagnosticEditor = editor
        return (window, editor)
    }

    private func makeWindow(view: some View) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.rootViewController?.beginAppearanceTransition(true, animated: false)
        window.rootViewController?.endAppearanceTransition()
        window.layoutIfNeeded()
        return window
    }

    private func close(_ window: UIWindow) {
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
    }

    private func notifyEdit(_ field: UITextField) {
        field.sendActions(for: .editingChanged)
    }

    private func select(_ range: Range<Int>, in field: UITextField) throws {
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: range.lowerBound))
        let end = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: range.upperBound))
        field.selectedTextRange = field.textRange(from: start, to: end)
    }

    private func priceField(_ key: PriceFilterEditor.Field, in window: UIWindow) async throws -> UITextField {
        try await wait {
            window.layoutIfNeeded()
            if self.descendants(window).compactMap({ $0 as? UITextField }).count == 4 { return true }
            for scroll in self.descendants(window).compactMap({ $0 as? UIScrollView }) {
                let bottom = max(0, scroll.contentSize.height - scroll.bounds.height
                                 + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
            return false
        }
        let fields = descendants(window).compactMap { $0 as? UITextField }.sorted {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        }
        let index = try XCTUnwrap(PriceFilterEditor.Field.allCases.firstIndex(of: key))
        return fields[index]
    }

    private func wait(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let fields = diagnosticWindow.map { descendants($0).compactMap { $0 as? UITextField }.map {
            "\($0.text ?? "nil") focused=\($0.isFirstResponder)"
        } } ?? []
        XCTFail("Price editor did not settle. Fields: \(fields); drafts: \(diagnosticEditor?.drafts ?? [:])",
                file: file, line: line)
        throw NSError(domain: "PriceFilterFieldTests", code: 1)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
