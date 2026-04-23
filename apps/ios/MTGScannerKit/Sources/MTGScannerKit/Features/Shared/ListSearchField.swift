import SwiftUI

struct ListSearchField: View {
    @Binding var text: String
    var prompt: String = "Search by title or set"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsTextSecondary)
            TextField(prompt, text: $text)
                .font(.geist(.body))
                .foregroundStyle(Color.dsTextPrimary)
                .focused($focused)
                .onSubmit { focused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(Color.dsSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.dsBorder, lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.dsBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder).frame(height: 0.5)
        }
        .onAppear { focused = true }
    }
}
