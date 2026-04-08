import Foundation

struct PriceFetchRequest {
    let id: UUID
    let name: String
    let scryfallId: String?
    let isFoil: Bool

    init(item: CollectionItem) {
        self.id = item.id
        self.name = item.title
        self.scryfallId = item.scryfallId
        self.isFoil = item.foil
    }
}
