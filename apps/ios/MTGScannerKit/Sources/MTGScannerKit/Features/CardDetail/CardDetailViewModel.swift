import Foundation
import UIKit

extension String {
    /// Returns `self` if non-empty, otherwise `nil`. Useful for optional chaining with `??`.
    var nonEmpty: String? { isEmpty ? nil : self }
}

@MainActor
@Observable
final class CardDetailViewModel {
    var card: RecognizedCard
    let cropImage: UIImage?

    var showingCropImage = false
    var selectedPrinting: CardPrinting?
    var cardPrice: CardPrice?
    var isLoadingPrice = false

    // Editable correction fields
    var editTitle: String
    var editEdition: String
    var editCollectorNumber: String
    var editFoil: Bool

    init(card: RecognizedCard, cropImage: UIImage?) {
        self.card = card
        self.cropImage = cropImage
        self.editTitle = card.title ?? ""
        self.editEdition = card.edition ?? ""
        self.editCollectorNumber = card.collectorNumber ?? ""
        self.editFoil = card.foil ?? false
    }

    private var displayPrinting: CardPrinting { selectedPrinting ?? CardPrinting(card: card) }

    var displayImageUrl: URL? {
        guard let urlString = displayPrinting.imageUrl else { return nil }
        return URL(string: urlString)
    }

    var displayTitle: String {
        editTitle.nonEmpty ?? displayPrinting.name
    }

    var displayEdition: String {
        editEdition.nonEmpty ?? displayPrinting.setName ?? displayPrinting.setCode
    }

    var displaySetCode: String {
        displayPrinting.setCode
    }

    var displayCollectorNumber: String {
        editCollectorNumber.nonEmpty ?? displayPrinting.collectorNumber ?? ""
    }

    var displayRarity: String? {
        displayPrinting.rarity
    }

    var displayTypeLine: String? {
        displayPrinting.typeLine
    }

    var displayOracleText: String? {
        displayPrinting.oracleText
    }

    var displayManaCost: String? {
        displayPrinting.manaCost
    }

    var displayPower: String? {
        displayPrinting.power
    }

    var displayToughness: String? {
        displayPrinting.toughness
    }

    var displayLoyalty: String? {
        displayPrinting.loyalty
    }

    var displayDefense: String? {
        displayPrinting.defense
    }

    var displaySetSymbolUrl: URL? {
        let urlString = displayPrinting.setSymbolUrl
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var displayCardKingdomUrl: URL? {
        let foil = editFoil
        let foilUrl = displayPrinting.cardKingdomFoilUrl
        let normalUrl = displayPrinting.cardKingdomUrl
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

    func loadPrice(using appModel: AppModel) async {
        let name = displayTitle
        guard !name.isEmpty else { return }
        let scryfallId = displayPrinting.scryfallId
        let requestedFoil = editFoil
        let requestedPrinting = displayPrinting
        let isRefresh = cardPrice != nil
        if !isRefresh { isLoadingPrice = true }
        do {
            let price = try await appModel.fetchPrice(
                name: name, scryfallId: scryfallId, isFoil: requestedFoil
            )
            guard matchesPriceRequest(name: name, printing: requestedPrinting, foil: requestedFoil) else { return }
            cardPrice = price
        } catch {
            guard matchesPriceRequest(name: name, printing: requestedPrinting, foil: requestedFoil) else { return }
            print("[CardDetail] Price lookup failed: \(error.localizedDescription)")
            cardPrice = nil
        }
        isLoadingPrice = false
    }

    private func matchesPriceRequest(name: String, printing: CardPrinting, foil: Bool) -> Bool {
        displayTitle == name && editFoil == foil
            && displayPrinting == printing
    }

    func saveCorrection(to appModel: AppModel) {
        var correction = CardCorrection(from: card)
        correction.title = editTitle
        correction.edition = editEdition
        correction.collectorNumber = editCollectorNumber
        correction.foil = editFoil
        correction.selectedPrintingSnapshot = selectedPrinting
        appModel.saveCorrection(correction)
    }
}
