import SwiftUI

struct ContentView: View {
    @ObservedObject var document: OrdoDocument
    @ObservedObject var settings: AppSettings
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 10) {
            header
            HighlightingTextView(
                text: $document.text,
                taskStates: settings.taskStates,
                onInsertTodo: { index, undoManager in
                    document.insertTodoEntry(
                        atCharacterIndex: index,
                        insertAfterLine: true,
                        undoManager: undoManager
                    )
                }
            )
            .padding(.vertical, 4)
            .padding(.horizontal, -2)
            .frame(minHeight: 320)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
        .frame(minWidth: 360, minHeight: 320)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack {
                Spacer()
                VStack(alignment: .center, spacing: 2) {
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
