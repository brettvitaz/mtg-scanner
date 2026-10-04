import SwiftData
import SwiftUI
import UIKit

private struct UndoSelectedTabKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var undoSelectedTab: Int? {
        get { self[UndoSelectedTabKey.self] }
        set { self[UndoSelectedTabKey.self] = newValue }
    }
}

struct CardDeleteUndoModifier: ViewModifier {
    let scope: CardDeleteUndoScope
    let name: String
    let blocked: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoSelectedTab) private var selectedTab
    @Environment(\.scenePhase) private var scenePhase
    @State private var pageVisible = false
    @State private var confirmation: PendingCardDeletion?
    @State private var errorMessage: String?

    private var availability: CardDeleteUndoAvailability {
        CardDeleteUndoAvailability(
            selectedTab: selectedTab, pageVisible: pageVisible, blocked: blocked,
            sceneActive: scenePhase == .active, editingText: UndoInteractionContext.isEditingText
        )
    }

    func body(content: Content) -> some View {
        content
            .toolbar { undoToolbar }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; confirmation = nil }
            .onChange(of: scenePhase) { _, phase in if phase != .active { confirmation = nil } }
            .onChange(of: selectedTab) { _, _ in confirmation = nil }
            .onChange(of: blocked) { _, blocked in if blocked { confirmation = nil } }
            .onShake { requestConfirmation() }
            .alert("Undo Delete?", isPresented: confirmationPresented, presenting: confirmation) { deletion in
                Button("Undo") { restore(deletion) }
                Button("Cancel", role: .cancel) { confirmation = nil }
            } message: { deletion in
                Text(deletion.message(destination: name))
            }
            .alert("Couldn't Restore Cards", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ToolbarContentBuilder
    private var undoToolbar: some ToolbarContent {
        if availability.allows(scope), let deletion = appModel.deleteUndo.deletion(in: scope) {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo Delete", systemImage: "arrow.uturn.backward") { restore(deletion) }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Undo delete in \(name)")
                    .accessibilityHint(deletion.message(destination: name))
            }
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func requestConfirmation() {
        guard availability.allowsShake(scope, shakeEnabled: UIAccessibility.isShakeToUndoEnabled),
              confirmation == nil, errorMessage == nil, !UndoInteractionContext.hasPresentation else { return }
        confirmation = appModel.deleteUndo.deletion(in: scope)
    }

    private func restore(_ deletion: PendingCardDeletion) {
        guard availability.allows(scope) else { return }
        do {
            try appModel.deleteUndo.restore(
                in: scope, deletionID: deletion.id, context: modelContext, commit: modelContext.save
            )
            confirmation = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            confirmation = nil
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    func cardDeleteUndo(scope: CardDeleteUndoScope, name: String, blocked: Bool) -> some View {
        modifier(CardDeleteUndoModifier(scope: scope, name: name, blocked: blocked))
    }
}

@MainActor
private enum UndoInteractionContext {
    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    static var isEditingText: Bool {
        guard let window else { return false }
        return containsTextResponder(window)
    }

    static var hasPresentation: Bool { window?.rootViewController?.presentedViewController != nil }

    private static func containsTextResponder(_ view: UIView) -> Bool {
        if view.isFirstResponder, view is any UITextInput { return true }
        return view.subviews.contains(where: containsTextResponder)
    }
}
