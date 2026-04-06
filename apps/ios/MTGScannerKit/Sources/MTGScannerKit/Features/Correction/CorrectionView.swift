import SwiftUI

struct CorrectionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let card: RecognizedCard

    @State private var title: String = ""
    @State private var edition: String = ""
    @State private var collectorNumber: String = ""
    @State private var foil: Bool = false
    @State private var saved = false

    var body: some View {
        // swiftlint:disable:next closure_body_length
        NavigationStack {
            Form {
                Section("Card Identity") {
                    LabeledContent("Confidence") {
                        ConfidenceBadge(value: card.confidence)
                    }

                    LabeledTextField("Title", text: $title, placeholder: "e.g. Lightning Bolt")
                    LabeledTextField("Edition", text: $edition, placeholder: "e.g. Magic 2010")
                    LabeledTextField("Collector #", text: $collectorNumber, placeholder: "e.g. 146")
                }

                Section("Attributes") {
                    Toggle("Foil", isOn: $foil)
                }

                if let notes = card.notes {
                    Section("Recognition Notes") {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { populateFields() }
            .overlay {
                if saved {
                    SavedBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func populateFields() {
        let existing = appModel.correction(for: card)
        title = existing.title
        edition = existing.edition
        collectorNumber = existing.collectorNumber
        foil = existing.foil
    }

    private func saveAndDismiss() {
        var correction = CardCorrection(from: card)
        correction.title = title
        correction.edition = edition
        correction.collectorNumber = collectorNumber
        correction.foil = foil
        appModel.saveCorrection(correction)

        withAnimation { saved = true }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            dismiss()
        }
    }
}

// MARK: - Helpers

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SavedBanner: View {
    var body: some View {
        VStack {
            Label("Correction saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.green, in: Capsule())
                .padding(.top, 12)
            Spacer()
        }
    }
}

struct ConfidenceBadge: View {
    let value: Double

    private var color: Color {
        switch value {
        case 0.85...: return .green
        case 0.6..<0.85: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(width: 80, height: 8)

            Text("\(Int(value * 100))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
