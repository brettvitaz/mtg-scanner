import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack(path: $appModel.resultsNavigationPath) {
            Group {
                if appModel.latestResult.cards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Results")
            .navigationDestination(for: RecognizedCard.self) { card in
                CardDetailView(card: card)
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
                    NavigationLink(value: card) {
                        CardRow(card: card, correction: appModel.corrections[card.id])
                    }
                }
            } header: {
                HStack {
                    Text("Recognized Cards")
                    Spacer()
                    Text("\(appModel.latestResult.cards.count) card(s)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - CardRow

private struct CardRow: View {
    let card: RecognizedCard
    let correction: CardCorrection?

    var body: some View {
        HStack(spacing: 12) {
            cardThumbnail
            cardInfo
        }
        .padding(.vertical, 4)
    }

    private var cardThumbnail: some View {
        Group {
            if let urlString = card.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 60, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(correction?.title.nonEmpty ?? card.title ?? "Unknown card")
                .font(.headline)
                .lineLimit(2)
            if let edition = correction?.edition.nonEmpty ?? card.edition {
                Text(edition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let cn = correction?.collectorNumber.nonEmpty ?? card.collectorNumber {
                Text("#\(cn)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Hashable conformance for NavigationLink

extension RecognizedCard: Hashable {
    static func == (lhs: RecognizedCard, rhs: RecognizedCard) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
