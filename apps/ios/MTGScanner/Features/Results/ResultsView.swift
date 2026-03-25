import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var cardToEdit: RecognizedCard?

    var body: some View {
        NavigationStack {
            Group {
                if appModel.latestResult.cards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Results")
            .sheet(item: $cardToEdit) { card in
                CorrectionView(card: card)
                    .environmentObject(appModel)
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No results yet")
                .font(.title3.bold())
            Text("Scan a card to see recognition results here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardList: some View {
        List {
            if let filename = appModel.lastUploadedFilename {
                Section("Latest Request") {
                    Label(filename, systemImage: "doc.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(appModel.latestResult.cards) { card in
                    CardRow(card: card, correction: appModel.corrections[card.id])
                        .contentShape(Rectangle())
                        .onTapGesture { cardToEdit = card }
                }
            } header: {
                HStack {
                    Text("Recognized Cards")
                    Spacer()
                    Text("\(appModel.latestResult.cards.count) card(s)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tap a card to edit and correct its fields.")
                    .font(.footnote)
            }
        }
    }
}

// MARK: - CardRow

private struct CardRow: View {
    let card: RecognizedCard
    let correction: CardCorrection?

    private var displayTitle: String {
        let t = correction?.title ?? card.title ?? "Unknown card"
        return t.isEmpty ? (card.title ?? "Unknown card") : t
    }

    private var displayEdition: String? {
        let e = correction?.edition ?? card.edition
        return (e?.isEmpty == false) ? e : nil
    }

    private var displayCollector: String? {
        let c = correction?.collectorNumber ?? card.collectorNumber
        return (c?.isEmpty == false) ? c : nil
    }

    private var isFoil: Bool {
        correction?.foil ?? card.foil ?? false
    }

    private var isCorrected: Bool { correction != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle)
                    .font(.headline)
                if isFoil {
                    Text("FOIL")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple, in: Capsule())
                }
                Spacer()
                if isCorrected {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .imageScale(.small)
                }
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }

            // Edition + collector
            if let edition = displayEdition {
                HStack(spacing: 4) {
                    Text(edition)
                    if let cn = displayCollector {
                        Text("·")
                        Text("#\(cn)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            // Confidence bar
            ConfidenceBadge(value: card.confidence)

            // Notes
            if let notes = card.notes, !isCorrected {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
