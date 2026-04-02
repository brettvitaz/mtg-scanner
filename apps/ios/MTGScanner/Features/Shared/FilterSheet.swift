import SwiftUI

/// Sheet for configuring card filters across set, rarity, foil, color identity, type, and price.
struct FilterSheet: View {
    @Bindable var filterState: CardFilterState
    let items: [CollectionItem]

    @Environment(\.dismiss) private var dismiss

    private var availableSets: [String] {
        Array(Set(items.map(\.edition))).sorted()
    }

    private var availableTypes: [String] {
        let types = items.map { primaryCardType(from: $0.typeLine) }
        return Array(Set(types)).sorted()
    }

    private var hasPrices: Bool {
        items.contains { $0.priceRetail != nil || $0.priceBuy != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                setSection
                raritySection
                foilSection
                colorSection
                typeSection
                if hasPrices {
                    priceSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { filterState.reset() }
                        .disabled(!filterState.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    // MARK: - Sections

    private var setSection: some View {
        Section("Set") {
            ForEach(availableSets, id: \.self) { setName in
                filterToggleRow(label: setName, isSelected: filterState.selectedSets.contains(setName)) {
                    filterState.selectedSets.toggle(setName)
                }
            }
        }
    }

    private var raritySection: some View {
        Section("Rarity") {
            HStack(spacing: 8) {
                ForEach(RarityFilter.allCases) { rarity in
                    let selected = filterState.selectedRarities.contains(rarity)
                    Button {
                        filterState.selectedRarities.toggle(rarity)
                    } label: {
                        Text(rarity.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var foilSection: some View {
        Section {
            Toggle("Foil only", isOn: $filterState.foilOnly)
        }
    }

    private var colorSection: some View {
        Section("Color Identity") {
            HStack(spacing: 10) {
                ForEach(ColorFilter.allCases) { color in
                    let selected = filterState.selectedColors.contains(color)
                    Button {
                        filterState.selectedColors.toggle(color)
                    } label: {
                        Text(color.rawValue)
                            .font(.headline.bold())
                            .frame(width: 36, height: 36)
                            .background(selected ? colorBackground(color) : Color.secondary.opacity(0.15))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var typeSection: some View {
        Section("Card Type") {
            ForEach(availableTypes, id: \.self) { type in
                filterToggleRow(label: type, isSelected: filterState.selectedCardTypes.contains(type)) {
                    filterState.selectedCardTypes.toggle(type)
                }
            }
        }
    }

    private var priceSection: some View {
        Section("Price") {
            priceRangeRow(label: "Min Sell", value: $filterState.priceRetailMin)
            priceRangeRow(label: "Max Sell", value: $filterState.priceRetailMax)
            priceRangeRow(label: "Min Buy", value: $filterState.priceBuyMin)
            priceRangeRow(label: "Max Buy", value: $filterState.priceBuyMax)
        }
    }

    // MARK: - Row Helpers

    private func filterToggleRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func priceRangeRow(label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Any", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func colorBackground(_ color: ColorFilter) -> Color {
        switch color {
        case .white:  return Color(red: 0.9, green: 0.85, blue: 0.7)
        case .blue:   return Color(red: 0.2, green: 0.5, blue: 0.9)
        case .black:  return Color(red: 0.25, green: 0.2, blue: 0.3)
        case .red:    return Color(red: 0.85, green: 0.25, blue: 0.2)
        case .green:  return Color(red: 0.2, green: 0.65, blue: 0.3)
        }
    }
}

// MARK: - Set Extension

private extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
