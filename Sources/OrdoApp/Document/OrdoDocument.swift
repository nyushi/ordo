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
    @Published private(set) var lastReloadedAt: Date?
    @Published private(set) var statusMessage: String?

    let fileURL: URL

    var statusLine: String {
        var components: [String] = []
        if let reloaded = lastReloadedAt {
            components.append("読込 \(Self.timeFormatter.string(from: reloaded))")
        }
        if let saved = lastSavedAt {
            components.append("保存 \(Self.timeFormatter.string(from: saved))")
        }
        if let statusMessage {
            components.append(statusMessage)
        }
        return components.joined(separator: " / ")
    }

    private let autosaveDelay: TimeInterval = 0.2
    private var saveWorkItem: DispatchWorkItem?
    private var fileDescriptor: CInt = -1
    private var fileSource: DispatchSourceFileSystemObject?
    private var isApplyingExternalChange = false
    private var ignoreWatcherEvents = false

    init() {
        fileURL = Self.prepareDataFile()
        text = ""
        loadFromDisk()
        setupFileWatcher()
    }

    func reloadFromDisk() {
        loadFromDisk()
    }

    func openInExternalEditor() {
        NSWorkspace.shared.open(fileURL)
    }

    func addInboxTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newLine = "** TODO \(trimmed)\n"
        let source = text as NSString
        let headerPattern = #"(?m)^\*+\s+Inbox.*$"#
        let headerRange = source.range(of: headerPattern, options: .regularExpression)
        if headerRange.location != NSNotFound {
            let lineRange = source.lineRange(for: headerRange)
            let insertIndex = lineRange.location + lineRange.length
            text = source.replacingCharacters(
                in: NSRange(location: insertIndex, length: 0),
                with: newLine
            )
        } else {
            var builder = text
            if !builder.hasSuffix("\n") {
                builder.append("\n")
            }
            builder.append("* Inbox\n")
            builder.append(newLine)
            text = builder
        }
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
        lastReloadedAt = Date()
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

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
