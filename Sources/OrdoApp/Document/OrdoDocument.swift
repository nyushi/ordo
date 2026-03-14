import AppKit
import Combine
import Foundation

@MainActor
final class OrdoDocument: ObservableObject {
    @Published var text: String {
        didSet {
            guard !isApplyingExternalChange else { return }
            scheduleSave()
        }
    }

    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var statusMessage: String?

    let fileURL: URL

    private let autosaveDelay: TimeInterval = 0.2
    private var saveWorkItem: DispatchWorkItem?
    private var fileDescriptor: CInt = -1
    private var fileSource: DispatchSourceFileSystemObject?
    private var isApplyingExternalChange = false
    private var ignoreWatcherEvents = false

    init() {
        fileURL = Self.prepareDataFile()
        if let initialText = try? String(contentsOf: fileURL, encoding: .utf8) {
            text = initialText
            NSLog("Ordo: loaded initial text (\(initialText.count) chars)")
        } else {
            text = ""
            NSLog("Ordo: failed to load initial text, starting empty")
        }
        setupFileWatcher()
    }

    func reloadFromDisk() {
        loadFromDisk()
    }

    func openInExternalEditor() {
        NSWorkspace.shared.open(fileURL)
    }
    
    func copyFilePathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        statusMessage = "パスをコピーしました"
    }

    @discardableResult
    func insertTodoEntry(
        atCharacterIndex index: Int,
        insertAfterLine: Bool = false,
        undoManager: UndoManager?
    ) -> Int? {
        let source = text as NSString
        let clampedIndex = max(0, min(source.length, index))
        var insertionIndex = clampedIndex

        let baseLineLocation: Int
        if insertAfterLine {
            insertionIndex = clampedIndex
            baseLineLocation = max(0, insertionIndex - 1)
        } else {
            let currentLineRange = source.lineRange(for: NSRange(location: clampedIndex, length: 0))
            insertionIndex = currentLineRange.location
            baseLineLocation = currentLineRange.location
        }

        let baseLineRange = source.lineRange(for: NSRange(location: baseLineLocation, length: 0))
        let baseLineString = source.substring(with: baseLineRange)
        let indentCount = baseLineString.prefix { $0 == " " || $0 == "\t" }.count
        let indent = String(baseLineString.prefix(indentCount))

        let level = headingLevelBefore(lineStart: insertionIndex, in: source) ?? 2
        let stars = String(repeating: "*", count: max(1, level))
        let todoLine = "\(indent)\(stars) TODO "
        let todoLineLength = (todoLine as NSString).length
        var prefix = ""
        if insertAfterLine {
            let needsNewline = insertionIndex > 0 && source.character(at: insertionIndex - 1) != 10
            if needsNewline {
                prefix = "\n"
            }
        }
        let insertionText = "\(prefix)\(todoLine)\n"
        let caretIndex = insertionIndex + (prefix as NSString).length + todoLineLength
        let updated = source.replacingCharacters(
            in: NSRange(location: insertionIndex, length: 0),
            with: insertionText
        )
        applyProgrammaticChange(updated, undoManager: undoManager, actionName: "TODO を挿入")
        return caretIndex
    }

    deinit {
        fileSource?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}

// MARK: - File IO

private extension OrdoDocument {
    func applyProgrammaticChange(_ newText: String, undoManager: UndoManager?, actionName: String) {
        let previous = text
        guard previous != newText else { return }
        text = newText
        undoManager?.registerUndo(withTarget: self) { document in
            document.applyProgrammaticChange(previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    func headingLevelBefore(lineStart: Int, in source: NSString) -> Int? {
        guard lineStart > 0 else { return nil }
        var foundLevel: Int?
        let searchRange = NSRange(location: 0, length: lineStart)
        source.enumerateSubstrings(in: searchRange, options: [.byLines, .reverse]) { substring, _, _, stop in
            guard let line = substring else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            let level = trimmed.prefix { $0 == "*" }.count
            if level > 0 {
                foundLevel = level
            }
            stop.pointee = true
        }
        return foundLevel
    }

    static func prepareDataFile() -> URL {
        let fm = FileManager.default
        let baseDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Ordo", isDirectory: true)

        do {
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("Ordo: failed to create data directory: \(error)")
        }

        let fileURL = baseDirectory.appendingPathComponent("main.org")
        if !fm.fileExists(atPath: fileURL.path) {
            do {
                try defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Ordo: failed to write template: \(error)")
            }
        }
        return fileURL
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveCurrentText()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    func saveCurrentText() {
        ignoreWatcherEvents = true
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSavedAt = Date()
            statusMessage = nil
        } catch {
            statusMessage = "保存失敗: \(error.localizedDescription)"
        }
        ignoreWatcherEvents = false
    }

    func loadFromDisk() {
        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            statusMessage = "読込失敗: \(error.localizedDescription)"
            return
        }
        isApplyingExternalChange = true
        text = contents
        isApplyingExternalChange = false
    }

    func setupFileWatcher() {
        fileSource?.cancel()
        fileSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            NSLog("Ordo: failed to monitor \(fileURL.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if self.ignoreWatcherEvents { return }
            guard let currentSource = self.fileSource else { return }
            let flags = DispatchSource.FileSystemEvent(rawValue: currentSource.data)
            self.handleFileEvent(flags)
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source.resume()
        fileSource = source
    }

    func handleFileEvent(_ flags: DispatchSource.FileSystemEvent) {
        if flags.contains(.delete) || flags.contains(.rename) {
            recreateFileIfNeeded()
            setupFileWatcher()
            return
        }
        loadFromDisk()
    }

    func recreateFileIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            do {
                try OrdoDocument.defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                statusMessage = "初期ファイル作成失敗: \(error.localizedDescription)"
            }
        }
    }

    static let defaultTemplate = """
* Inbox
** TODO ここにタスクを書く

* Today
** TODO 今日扱うものを移す

* Archive
** DONE 初期テンプレート
"""

}
