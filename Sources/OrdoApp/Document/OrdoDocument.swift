import AppKit
import Combine
import Foundation

@MainActor
final class OrdoDocument: ObservableObject {
    @Published var text: String {
        didSet {
            NSLog("OrdoDocument: text didSet (chars=\(text.count))")
            guard !isApplyingExternalChange else { return }
            scheduleSave()
        }
    }

    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var statusMessage: String?

    let fileURL: URL

    private let autosaveDelay: TimeInterval
    private var saveWorkItem: DispatchWorkItem?
    private var watchDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var isApplyingExternalChange = false
    private var ignoreWatcherEvents = false

    init(fileURL: URL? = nil, autosaveDelay: TimeInterval = 0.2) {
        self.autosaveDelay = autosaveDelay
        let resolvedURL = fileURL ?? Self.defaultDataFileURL()
        self.fileURL = resolvedURL
        NSLog("OrdoDocument monitoring \(resolvedURL.path)")
        Self.prepareDataFile(at: resolvedURL)
        if let initialText = try? String(contentsOf: resolvedURL, encoding: .utf8) {
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
        statusMessage = "Copied path to clipboard"
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
        applyProgrammaticChange(updated, undoManager: undoManager, actionName: "Insert TODO")
        return caretIndex
    }

    deinit {
        directorySource?.cancel()
        if watchDescriptor >= 0 {
            close(watchDescriptor)
        }
    }
}

// MARK: - File IO

private extension OrdoDocument {
    func applyProgrammaticChange(_ newText: String, undoManager: UndoManager?, actionName: String) {
        let previous = text
        guard previous != newText else { return }
        text = newText
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            Task { @MainActor in
                document.applyProgrammaticChange(previous, undoManager: undoManager, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
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

    static func defaultDataFileURL() -> URL {
        AppSettings.defaultOrgFileURL()
    }

    static func prepareDataFile(at url: URL) {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Ordo: failed to create data directory: \(error)")
        }

        if !fm.fileExists(atPath: url.path) {
            do {
                try defaultTemplate.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Ordo: failed to write template: \(error)")
            }
        }
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveCurrentText()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    func cancelPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
    }

    func saveCurrentText() {
        cancelPendingSave()
        ignoreWatcherEvents = true
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSavedAt = Date()
            statusMessage = nil
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
        ignoreWatcherEvents = false
    }

    func loadFromDisk(retryCount: Int = 3) {
        cancelPendingSave()
        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            if retryCount > 0 {
                let delay: DispatchTimeInterval = .milliseconds(80)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.loadFromDisk(retryCount: retryCount - 1)
                }
            } else {
                statusMessage = "Load failed: \(error.localizedDescription)"
            }
            return
        }
        NSLog("OrdoDocument: reloading \(fileURL.path)")
        isApplyingExternalChange = true
        text = contents
        isApplyingExternalChange = false
    }

    func setupFileWatcher(retryCount: Int = 5) {
        directorySource?.cancel()
        directorySource = nil
        if watchDescriptor >= 0 {
            close(watchDescriptor)
            watchDescriptor = -1
        }

        let directoryPath = fileURL.deletingLastPathComponent().path
        watchDescriptor = open(directoryPath, O_EVTONLY)
        guard watchDescriptor >= 0 else {
            if retryCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                    self?.setupFileWatcher(retryCount: retryCount - 1)
                }
            } else {
                NSLog("Ordo: failed to monitor directory \(directoryPath)")
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            guard let src = source else { return }
            let flags = DispatchSource.FileSystemEvent(rawValue: src.data)
            if self.ignoreWatcherEvents { return }
            self.handleFileEvent(flags)
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.watchDescriptor, fd >= 0 {
                close(fd)
            }
            self?.watchDescriptor = -1
        }

        source.resume()
        directorySource = source
    }

    func handleFileEvent(_ flags: DispatchSource.FileSystemEvent) {
        NSLog("OrdoDocument: handleFileEvent flags=\(flags.rawValue)")
        if flags.contains(.delete) {
            recreateFileIfNeeded()
        }
        if flags.contains(.delete) || flags.contains(.rename) {
            setupFileWatcher()
        }
        loadFromDisk()
    }

    func recreateFileIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            do {
                try OrdoDocument.defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                statusMessage = "Failed to create initial file: \(error.localizedDescription)"
            }
        }
    }

    static let defaultTemplate = """
* Inbox
** TODO Write tasks here

* Today
** TODO Move items you'll handle today

* Archive
** DONE Initial template
"""

}
