import SwiftUI

struct ContentView: View {
    @ObservedObject var document: OrdoDocument
    @State private var quickEntryText: String = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            quickEntryBar
            HighlightingTextView(text: $document.text)
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
                    Text(document.fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    document.reloadFromDisk()
                } label: {
                    Label("再読込", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)

                Button {
                    document.openInExternalEditor()
                } label: {
                    Label("外部編集", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
            }

            Text(document.fileURL.path)
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if !document.statusLine.isEmpty {
                Text(document.statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickEntryBar: some View {
        HStack(spacing: 8) {
            TextField("Inbox に TODO を追加", text: $quickEntryText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addQuickEntry)

            Button {
                addQuickEntry()
            } label: {
                Label("追加", systemImage: "plus.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func addQuickEntry() {
        let trimmed = quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.addInboxTask(title: trimmed)
        quickEntryText = ""
    }
}
