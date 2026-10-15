import Foundation
import SwiftData

@MainActor
enum ResultCorrectionSave {
    static func toggleFoil(items: [CollectionItem], context: ModelContext, baseURL: String,
                           commit: (() throws -> Void)? = nil) throws {
        try context.save()
        let snapshots = items.map(CardItemSnapshot.init)
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            for item in items {
                let previous = FeedbackIdentification(item)
                item.toggleFoilUnconditionally()
                try RecognitionFeedbackEvent.capture(item: item, previous: previous, context: context, baseURL: baseURL)
            }
            try (commit ?? { try context.save() })()
        } catch {
            context.rollback()
            for (item, snapshot) in zip(items, snapshots) { snapshot.restoreValues(on: item) }
            throw error
        }
    }
}
