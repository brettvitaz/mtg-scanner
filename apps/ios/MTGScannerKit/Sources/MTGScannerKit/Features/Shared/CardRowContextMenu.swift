import SwiftUI
import UIKit

/// Hosts the row so UIKit owns preview presentation and preview-to-detail commits.
struct CardRowContextMenu<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let item: CollectionItem
    let actions: CardRowMenuActions
    let onPresent: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.sizingOptions = .intrinsicContentSize
        controller.view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        context.coordinator.parent = self
        controller.rootView = content
        controller.view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context
    ) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(
            width: proposal.width ?? 390, height: proposal.height ?? .greatestFiniteMagnitude
        ))
    }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: CardRowContextMenu

        init(parent: CardRowContextMenu) { self.parent = parent }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard parent.actions.isAvailable else { return nil }
            parent.onPresent()
            let item = parent.item
            let actions = parent.actions
            let bounds = interaction.view?.window?.bounds.size ?? CGSize(width: 390, height: 844)
            return UIContextMenuConfiguration(identifier: item.id.uuidString as NSString) {
                let controller = UIHostingController(rootView: CardRowPreview(item: item))
                controller.view.backgroundColor = .clear
                controller.preferredContentSize = CardRowPreview.size(
                    in: bounds, hasArtwork: item.imageUrl.flatMap(URL.init(string:)) != nil
                )
                return controller
            } actionProvider: { _ in
                actions.menu(isFoil: item.foil)
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
            animator: any UIContextMenuInteractionCommitAnimating
        ) {
            let navigate = parent.actions.navigate
            animator.addCompletion { navigate?() }
        }
    }
}

@MainActor
struct CardRowMenuActions {
    var transfer: (() -> Void)?
    var toggleFoil: (() -> Void)?
    var delete: (() -> Void)?
    var navigate: (() -> Void)?

    var isAvailable: Bool { transfer != nil || toggleFoil != nil || delete != nil }

    func menu(isFoil: Bool) -> UIMenu {
        var primary: [UIMenuElement] = []
        if let transfer {
            primary.append(UIAction(title: "Copy/Move", image: UIImage(systemName: "doc.on.doc")) { _ in transfer() })
        }
        if let toggleFoil {
            primary.append(UIAction(
                title: isFoil ? "Set as Non-Foil" : "Set as Foil", image: UIImage(systemName: "sparkles")
            ) { _ in toggleFoil() })
        }
        var groups: [UIMenuElement] = []
        if !primary.isEmpty { groups.append(UIMenu(options: .displayInline, children: primary)) }
        if let delete {
            let action = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                delete()
            }
            groups.append(UIMenu(options: .displayInline, children: [action]))
        }
        return UIMenu(children: groups)
    }
}
