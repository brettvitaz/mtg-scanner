import Foundation

struct PriceFetchRequest {
    let id: UUID
    let name: String
    let scryfallId: String?
    let isFoil: Bool
    let setCode: String?
    let collectorNumber: String?

    func matches(_ item: CollectionItem) -> Bool {
        id == item.id && name == item.title && scryfallId == item.scryfallId && isFoil == item.foil
            && setCode == item.setCode && collectorNumber == item.collectorNumber
    }

    init(item: CollectionItem) {
        self.id = item.id
        self.name = item.title
        self.scryfallId = item.scryfallId
        self.isFoil = item.foil
        self.setCode = item.setCode
        self.collectorNumber = item.collectorNumber
    }
}
