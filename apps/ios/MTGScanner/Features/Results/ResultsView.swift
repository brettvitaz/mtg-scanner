import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let filename = appModel.lastUploadedFilename {
                    Section("Latest Request") {
                        Text(filename)
                            .font(.subheadline)
                    }
                }

                Section("Recognized Cards") {
                    ForEach(appModel.latestResult.cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.title ?? "Unknown card")
                                .font(.headline)

                            if let edition = card.edition {
                                Text(edition)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Confidence: \(Int(card.confidence * 100))%")
                                .font(.footnote)

                            if let notes = card.notes {
                                Text(notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Results")
        }
    }
}
