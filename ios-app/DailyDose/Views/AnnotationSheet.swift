import SwiftUI

struct AnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var color: HighlightColor
    @FocusState private var isEditorFocused: Bool

    let quote: String?
    let onSave: (String, HighlightColor) -> Void
    let onDelete: (() -> Void)?

    private var isEditing: Bool { onDelete != nil }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(
        quote: String?,
        noteText: String,
        color: HighlightColor,
        onSave: @escaping (String, HighlightColor) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.quote = quote
        self._text = State(initialValue: noteText)
        self._color = State(initialValue: color)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let quote {
                        Text(color.highlighting(quote))
                            .font(.callout)
                            .lineLimit(4)
                            .accessibilityLabel("Highlighted passage: \(quote)")
                    }

                    swatches

                    editor

                    if let onDelete {
                        Button("Delete Note", systemImage: "trash", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(isEditing ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedText, color)
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { isEditorFocused = !isEditing }
    }

    private var swatches: some View {
        HStack(spacing: 12) {
            ForEach(HighlightColor.allCases, id: \.self) { option in
                SwatchButton(color: option, isSelected: option == color) { color = option }
                    .accessibilityLabel(option.name)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight colour")
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($isEditorFocused)
            .frame(minHeight: 140)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write a note")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Note")
    }
}
