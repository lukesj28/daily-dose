import SwiftUI

struct AnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isTextFieldFocused: Bool

    let initialText: String
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?

    private var isEditing: Bool { onDelete != nil }

    init(noteText: String, onSave: @escaping (String) -> Void, onDelete: (() -> Void)? = nil) {
        self.initialText = noteText
        self._text = State(initialValue: noteText)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEditing ? "Edit Note" : "Add Note")
                    .font(.headline)

                TextField("Write your note...", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)

                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }

                if let onDelete {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Note")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
