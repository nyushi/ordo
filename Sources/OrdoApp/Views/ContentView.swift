import SwiftUI

struct ContentView: View {
    @ObservedObject var document: OrdoDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 10) {
            header
            HighlightingTextView(
                text: $document.text,
                onInsertTodo: { index, undoManager in
                    document.insertTodoEntry(
                        atCharacterIndex: index,
                        insertAfterLine: true,
                        undoManager: undoManager
                    )
                }
            )
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: NSColor.textBackgroundColor.withAlphaComponent(0.35)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08))
                )
                .frame(minHeight: 320)
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ordo")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(document.fileURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            document.copyFilePathToClipboard()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .imageScale(.small)
                        }
                        .buttonStyle(.borderless)
                        .help("パスをコピー")
                    }
                }

                Spacer()
            }
        }
    }

}
