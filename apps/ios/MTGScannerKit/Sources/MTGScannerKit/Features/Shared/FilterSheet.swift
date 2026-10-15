import SwiftUI

/// Sheet for configuring card filters across set, rarity, foil, color identity, type, and price.
struct FilterSheet: View {
    @Bindable var filterState: CardFilterState
    let items: [CollectionItem]

    @Environment(\.dismiss) private var dismiss
    @State private var priceEditor: PriceFilterEditor
    @FocusState private var focusedPrice: PriceFilterEditor.Field?

    init(filterState: CardFilterState, items: [CollectionItem], priceEditor: PriceFilterEditor? = nil) {
        self.filterState = filterState
        self.items = items
        _priceEditor = State(initialValue: priceEditor ?? PriceFilterEditor(filterState: filterState))
    }

    private var usesKeyboardInset: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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
            ScrollViewReader { proxy in
                filterList
                    .task {
                        if let field = priceEditor.focusedField {
                            proxy.scrollTo(field, anchor: .center)
                            focusedPrice = field
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: UIResponder.keyboardDidShowNotification
                    )) { _ in
                        if let field = focusedPrice { proxy.scrollTo(field, anchor: .center) }
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // iPad can omit native keyboard toolbar items; retain the same actions above its keyboard.
            if usesKeyboardInset, focusedPrice != nil {
                HStack { keyboardButtons }
                    .padding(.horizontal)
                    .background(.bar)
            }
        }
    }

    private var filterList: some View {
        List {
            setSection
            raritySection
            foilSection
            colorSection
            typeSection
            buyingSection
            if hasPrices {
                priceSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset") { priceEditor.reset() }
                    .accessibilityIdentifier("price-filter-reset")
                    .disabled(!priceEditor.canReset)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { if priceEditor.finish() { dismiss() } }
                    .accessibilityIdentifier("price-filter-done")
                    .bold()
            }
            ToolbarItemGroup(placement: .keyboard) {
                if !usesKeyboardInset { keyboardButtons }
            }
        }
        .onChange(of: focusedPrice) { _, field in
            if !priceEditor.move(to: field) { focusedPrice = priceEditor.focusedField }
        }
        .onChange(of: priceEditor.focusedField) { _, field in focusedPrice = field }
    }

    @ViewBuilder
    private var keyboardButtons: some View {
        Button("Previous", systemImage: "chevron.up") { priceEditor.previous() }
            .accessibilityIdentifier("price-previous")
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!priceEditor.canMovePrevious)
        Button("Next", systemImage: "chevron.down") { priceEditor.next() }
            .accessibilityIdentifier("price-next")
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!priceEditor.canMoveNext)
        Spacer()
        Button("Done", systemImage: "checkmark") { _ = priceEditor.move(to: nil) }
            .accessibilityIdentifier("price-keyboard-done")
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
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
                    .accessibilityLabel(rarity.displayName)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                    .accessibilityLabel("\(color.displayName) color identity")
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    private var buyingSection: some View {
        Section {
            Toggle("Show cards CK is buying", isOn: $filterState.ckBuyingOnly)
        } header: {
            Text("Card Kingdom")
        } footer: {
            Text("Shows cards with a confirmed buying quantity above zero. Unknown availability is excluded.")
        }
    }

    private var priceSection: some View {
        Section("Price") {
            ForEach(PriceFilterEditor.Field.allCases) { field in
                priceRangeRow(field).id(field)
            }
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
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func priceRangeRow(_ field: PriceFilterEditor.Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.rawValue)
                Spacer()
                TextField("Any", text: Binding(
                    get: { priceEditor.drafts[field] ?? "" },
                    set: { priceEditor.drafts[field] = $0 }
                ))
                    .accessibilityLabel(field.rawValue)
                    .accessibilityIdentifier(field.rawValue)
                    .autocorrectionDisabled(true)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 80)
                    .focused($focusedPrice, equals: field)
                    .submitLabel(field.next == nil ? .done : .next)
                    .onSubmit { priceEditor.submit() }
                if !(priceEditor.drafts[field] ?? "").isEmpty {
                    clearPriceButton(field)
                }
            }
            if let error = priceEditor.errors[field] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(field.rawValue): \(error)")
            }
        }
    }

    private func clearPriceButton(_ field: PriceFilterEditor.Field) -> some View {
        Button {
            priceEditor.clear(field)
            focusedPrice = field
        } label: {
            Image(systemName: "xmark.circle.fill")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Clear \(field.rawValue)")
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
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
