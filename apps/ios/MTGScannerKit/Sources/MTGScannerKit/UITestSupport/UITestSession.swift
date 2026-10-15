#if DEBUG
import Foundation
import SwiftData

/// Disk-backed state owned only by a single UI-test run, never the normal app store.
@MainActor
public final class UITestSession {
    public enum Mode: String {
        case fresh, resume, cleanup
    }

    public let mode: Mode
    public let container: ModelContainer
    public let appModel: AppModel
    let preferences: UserDefaults

    public init(runID: UUID, mode: Mode) throws {
        self.mode = mode
        let directory = Self.directory(runID: runID)
        let store = directory.appending(path: "cards.store")
        if mode != .resume {
            try Self.cleanup(runID: runID)
        } else if !FileManager.default.fileExists(atPath: store.path) {
            throw CocoaError(.fileNoSuchFile)
        }
        if mode != .cleanup {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let preferences = UserDefaults(suiteName: Self.suiteName(runID: runID)) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.preferences = preferences
        appModel = AppModel(preferences: preferences)
        let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
        let configuration = mode == .cleanup
            ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration(url: store)
        container = try ModelContainer(for: schema, configurations: [configuration])
        appModel.modelContext = container.mainContext
        if mode == .fresh {
            container.mainContext.insert(CollectionItem(
                title: "Lightning Bolt", edition: "Magic 2010", setCode: "M10", collectorNumber: "146"
            ))
            try container.mainContext.save()
        }
    }

    public static func cleanup(runID: UUID) throws {
        let directory = directory(runID: runID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        UserDefaults.standard.removePersistentDomain(forName: suiteName(runID: runID))
    }

    private static func directory(runID: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "UITestRuns", directoryHint: .isDirectory)
            .appending(path: runID.uuidString, directoryHint: .isDirectory)
    }

    private static func suiteName(runID: UUID) -> String {
        "com.brettvitaz.mtgscanner.ui-tests.\(runID.uuidString)"
    }
}
#endif
