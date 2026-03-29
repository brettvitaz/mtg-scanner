import Foundation
import UIKit

extension String {
    /// Returns `self` if non-empty, otherwise `nil`. Useful for optional chaining with `??`.
    var nonEmpty: String? { isEmpty ? nil : self }
}

@MainActor
final class CardDetailViewModel: ObservableObject {
    let card: RecognizedCard
    let cropImage: UIImage?

    @Published var showingCropImage = false
    @Published var printings: [CardPrinting] = []
    @Published var isLoadingPrintings = false
    @Published var selectedPrinting: CardPrinting?

    // Editable correction fields
    @Published var editTitle: String
    @Published var editEdition: String
    @Published var editCollectorNumber: String
    @Published var editFoil: Bool

    init(card: RecognizedCard, cropImage: UIImage?) {
        self.card = card
        self.cropImage = cropImage
        self.editTitle = card.title ?? ""
        self.editEdition = card.edition ?? ""
        self.editCollectorNumber = card.collectorNumber ?? ""
        self.editFoil = card.foil ?? false
    }

    var displayImageUrl: URL? {
        guard let urlString = selectedPrinting?.imageUrl ?? card.imageUrl else { return nil }
        return URL(string: urlString)
    }

    var displayTitle: String {
        editTitle.nonEmpty ?? selectedPrinting?.name ?? card.title ?? "Unknown card"
    }

    var displayEdition: String {
        editEdition.nonEmpty ?? selectedPrinting?.setName ?? card.edition ?? ""
    }

    var displaySetCode: String {
        selectedPrinting?.setCode ?? card.setCode ?? ""
    }

    var displayCollectorNumber: String {
        editCollectorNumber.nonEmpty ?? selectedPrinting?.collectorNumber ?? card.collectorNumber ?? ""
    }

    var displayRarity: String? {
        selectedPrinting?.rarity ?? card.rarity
    }

    var displayTypeLine: String? {
        selectedPrinting?.typeLine ?? card.typeLine
    }

    var displayOracleText: String? {
        selectedPrinting?.oracleText ?? card.oracleText
    }

    var displayPower: String? {
        selectedPrinting?.power ?? card.power
    }

    var displayToughness: String? {
        selectedPrinting?.toughness ?? card.toughness
    }

    var displayLoyalty: String? {
        selectedPrinting?.loyalty ?? card.loyalty
    }

    var displayDefense: String? {
        selectedPrinting?.defense ?? card.defense
    }

    var displaySetSymbolUrl: URL? {
        let urlString = selectedPrinting?.setSymbolUrl ?? card.setSymbolUrl
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var displayCardKingdomUrl: URL? {
        let foil = editFoil
        let foilUrl = selectedPrinting?.cardKingdomFoilUrl ?? card.cardKingdomFoilUrl
        let normalUrl = selectedPrinting?.cardKingdomUrl ?? card.cardKingdomUrl
        let urlString = (foil ? foilUrl : nil) ?? normalUrl
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var hasStats: Bool {
        displayPower != nil || displayLoyalty != nil || displayDefense != nil
    }

    var statsText: String? {
        if let power = displayPower, let toughness = displayToughness {
            return "\(power)/\(toughness)"
        }
        if let loyalty = displayLoyalty {
            return "Loyalty: \(loyalty)"
        }
        if let defense = displayDefense {
            return "Defense: \(defense)"
        }
        return nil
    }

    func loadPrintings(using appModel: AppModel) async {
        guard let name = card.title, !name.isEmpty else { return }
        isLoadingPrintings = true
        do {
            printings = try await appModel.fetchPrintings(name: name)
        } catch {
            printings = []
        }
        isLoadingPrintings = false
    }

    func selectPrinting(_ printing: CardPrinting) {
        selectedPrinting = printing
        editTitle = printing.name ?? editTitle
        editEdition = printing.setName ?? ""
        editCollectorNumber = printing.collectorNumber ?? ""
    }

    func saveCorrection(to appModel: AppModel) {
        var correction = CardCorrection(from: card)
        correction.title = editTitle
        correction.edition = editEdition
        correction.collectorNumber = editCollectorNumber
        correction.foil = editFoil
        appModel.saveCorrection(correction)
    }
}
