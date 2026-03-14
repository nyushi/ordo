import Foundation
import SwiftUI

struct HighlightingTextView: NSViewRepresentable {
    @Binding var text: String
    var taskStates: [String]
    var onInsertTodo: (Int, UndoManager?) -> Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textContainer = NSTextContainer(size: NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = OrgTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.font = Self.baseFont
        textView.textColor = NSColor.labelColor
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 40, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.backgroundColor = NSColor.clear
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.onInsertTodo = { [weak coordinator = context.coordinator] index in
            coordinator?.insertTodo(at: index)
        }
        textView.taskStates = taskStates
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.taskStates = taskStates
        context.coordinator.applyHighlighting()

        scrollView.documentView = textView
        textView.frame = scrollView.bounds
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.isUpdatingFromModel = true
            textView.string = text
            context.coordinator.applyHighlighting()
            context.coordinator.isUpdatingFromModel = false
        }
        if context.coordinator.taskStates != taskStates {
            context.coordinator.taskStates = taskStates
            if let orgView = textView as? OrgTextView {
                orgView.taskStates = taskStates
            }
            context.coordinator.applyHighlighting()
        }
        context.coordinator.applyPendingSelectionIfNeeded()
    }
}

extension HighlightingTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextView
        weak var textView: NSTextView?
        var isUpdatingFromModel = false
        var taskStates: [String] = [] {
            didSet {
                matcher = TaskStateMatcher(states: taskStates)
            }
        }
        private var matcher = TaskStateMatcher(states: [])
        private var pendingSelectionRange: NSRange?

        init(parent: HighlightingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard
                !isUpdatingFromModel,
                let textView
            else { return }

            let latest = textView.string
            parent.text = latest
            applyHighlighting()
        }

        func applyHighlighting() {
            guard let textStorage = textView?.textStorage else { return }
            let content = textStorage.string as NSString
            let fullRange = NSRange(location: 0, length: content.length)
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: HighlightingTextView.baseFont,
                .foregroundColor: NSColor.labelColor
            ]

            textStorage.beginEditing()
            textStorage.setAttributes(defaultAttrs, range: fullRange)

            content.enumerateSubstrings(in: fullRange, options: .byLines) { [weak self] substring, range, _, _ in
                guard let self else { return }
                guard let line = substring else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("*") {
                    textStorage.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.systemBlue
                    ], range: range)
                }

                if let match = self.matcher.match(inLineRange: range, string: content) {
                    self.applyStateHighlight(match: match, in: textStorage)
                }
            }

            textStorage.endEditing()
        }

        private func applyStateHighlight(match: TaskStateMatch, in textStorage: NSTextStorage) {
            let stateIndex = match.index
            let lastIndex = max(taskStates.count - 1, 0)
            if stateIndex == 0 {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.18)
                ], range: match.range)
            } else if stateIndex == lastIndex {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemGreen.withAlphaComponent(0.9),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            } else {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemBlue
                ], range: match.range)
            }
        }
        
        func insertTodo(at index: Int) {
            guard let textView else { return }
            let caretIndex = parent.onInsertTodo(index, textView.undoManager)
            guard let caretIndex else { return }
            let range = NSRange(location: caretIndex, length: 0)
            pendingSelectionRange = range
            applyPendingSelectionIfNeeded()
        }

        func applyPendingSelectionIfNeeded() {
            guard
                let textView,
                let pendingRange = pendingSelectionRange
            else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.isUpdatingFromModel = true
                if textView.string != self.parent.text {
                    textView.string = self.parent.text
                }
                self.applyHighlighting()
                self.isUpdatingFromModel = false
                textView.setSelectedRange(pendingRange)
                textView.scrollRangeToVisible(pendingRange)
                self.pendingSelectionRange = nil
            }
        }
    }

    static var baseFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }
}

private final class OrgTextView: NSTextView {
    var onInsertTodo: ((Int) -> Void)?
    var taskStates: [String] = [] {
        didSet {
            taskStateMatcher = TaskStateMatcher(states: taskStates)
            if taskStates.isEmpty {
                hideDoneButton()
            }
        }
    }
    private var taskStateMatcher = TaskStateMatcher(states: [])
    private var addButton: NSButton = {
        let image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add TODO")!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.isHidden = true
        button.alphaValue = 0.85
        button.contentTintColor = .systemOrange
        return button
    }()
    private var doneButton: NSButton = {
        let image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Mark complete")!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.isHidden = true
        button.contentTintColor = .systemGreen
        button.refusesFirstResponder = true
        return button
    }()
    private var currentStateMatch: TaskStateMatch?
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverInsertionIndex: Int?
    private var lastInsertionIndex: Int?
    private let buttonSize: CGFloat = 18
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        addSubview(addButton)
        addSubview(doneButton)
        addButton.target = self
        addButton.action = #selector(insertTodoFromButton)
        doneButton.target = self
        doneButton.action = #selector(toggleCompletionState)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateControlsForSelection()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        var handled = false
        if event.clickCount == 1 {
            handled = handleStateClick(event: event)
        }
        if handled { return }
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoverControls(for: event)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHoverControls(for: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideAddButton()
        hideDoneButton()
    }

    private func handleStateClick(event: NSEvent) -> Bool {
        guard
            let layoutManager,
            let textContainer,
            let textStorage
        else { return false }

        let viewPoint = convert(event.locationInWindow, from: nil)
        var location = viewPoint
        location.x -= textContainerOrigin.x
        location.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        if glyphIndex >= layoutManager.numberOfGlyphs { return false }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        let string = textStorage.string as NSString
        guard
            let match = taskStateMatcher.match(at: characterIndex, in: string),
            NSLocationInRange(characterIndex, match.range)
        else { return false }

        presentStateMenu(for: match, anchorInView: viewPoint)
        return true
    }
    
    private func updateHoverControls(for event: NSEvent) {
        guard
            let layoutManager,
            let textContainer,
            let textStorage
        else {
            hideAddButton()
            hideDoneButton()
            return
        }

        let rawLocation = convert(event.locationInWindow, from: nil)
        let buttonGuardX = bounds.width - textContainerInset.width - buttonSize - 4
        let freezeAddButton = rawLocation.x >= buttonGuardX && hoverInsertionIndex != nil

        var location = rawLocation
        location.x -= textContainerOrigin.x
        location.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            hideAddButton()
            hideDoneButton()
            return
        }

        var glyphLineRange = NSRange(location: 0, length: 0)
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &glyphLineRange,
            withoutAdditionalLayout: true
        )
        let rectInView = lineRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: characterIndex, length: 0))
        let insertionIndex = min(lineRange.location + lineRange.length, string.length)
        hoverInsertionIndex = insertionIndex
        lastInsertionIndex = insertionIndex

        if !freezeAddButton {
            positionAddButton(rectInView: rectInView)
        }
        updateDoneButton(lineRange: lineRange, rectInView: rectInView, string: string)
    }
    
    private func positionAddButton(rectInView: NSRect) {
        let inset = textContainerInset.width
        let buttonX = max(bounds.width - inset - buttonSize - 2, rectInView.minX)
        let buttonOrigin = NSPoint(
            x: buttonX,
            y: rectInView.minY + (rectInView.height - buttonSize) / 2
        )
        addButton.frame = NSRect(origin: buttonOrigin, size: NSSize(width: buttonSize, height: buttonSize))
        addButton.isHidden = false
    }

    private func hideAddButton() {
        addButton.isHidden = true
    }

    private func updateDoneButton(lineRange: NSRange, rectInView: NSRect, string: NSString) {
        guard
            !taskStates.isEmpty,
            let match = taskStateMatcher.match(inLineRange: lineRange, string: string)
        else {
            hideDoneButton()
            return
        }
        currentStateMatch = match
        let buttonX = max(6, textContainerOrigin.x - buttonSize - 4)
        let origin = NSPoint(
            x: buttonX,
            y: rectInView.minY + (rectInView.height - buttonSize) / 2
        )
        doneButton.frame = NSRect(origin: origin, size: NSSize(width: buttonSize, height: buttonSize))
        doneButton.isHidden = taskStates.count < 2
    }

    private func hideDoneButton() {
        doneButton.isHidden = true
        currentStateMatch = nil
    }
    
    @objc private func insertTodoFromButton() {
        let index = hoverInsertionIndex ?? lastInsertionIndex ?? textStorage?.length
        guard let index else { return }
        onInsertTodo?(index)
        hideAddButton()
    }

    @objc private func applyStateFromMenu(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? StateMenuPayload
        else { return }
        applyState(payload.state, to: payload.range)
    }

    @objc private func toggleCompletionState() {
        guard
            let match = currentStateMatch,
            taskStates.count >= 2
        else { return }
        let targetState: String
        if match.index == taskStates.count - 1 {
            targetState = taskStates.first ?? match.state
        } else {
            targetState = taskStates.last ?? match.state
        }
        applyState(targetState, to: match.range)
    }

    private func presentStateMenu(for match: TaskStateMatch, anchorInView anchor: NSPoint) {
        guard !taskStates.isEmpty else { return }
        let menu = NSMenu()
        for state in taskStates {
            let payload = StateMenuPayload(state: state, range: match.range)
            let item = NSMenuItem(title: state, action: #selector(applyStateFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = payload
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: anchor, in: self)
    }

    private func applyState(_ state: String, to range: NSRange) {
        guard let textStorage else { return }
        textStorage.replaceCharacters(in: range, with: state)
        let newRange = NSRange(location: range.location, length: (state as NSString).length)
        let normalized = state.uppercased()
        let index = taskStates.firstIndex(where: { $0.uppercased() == normalized }) ?? 0
        currentStateMatch = TaskStateMatch(range: newRange, state: state, index: index)
        needsDisplay = true
        didChangeText()
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        updateControlsForSelection()
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        updateControlsForSelection()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateControlsForSelection()
    }

    private func updateControlsForSelection() {
        guard
            let layoutManager,
            let textStorage
        else {
            hideAddButton()
            hideDoneButton()
            return
        }
        guard layoutManager.numberOfGlyphs > 0 else {
            hideAddButton()
            hideDoneButton()
            return
        }
        let caretLocation = min(selectedRange().location, textStorage.length)
        let characterIndex = max(0, min(caretLocation, max(textStorage.length - 1, 0)))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        var glyphLineRange = NSRange(location: 0, length: 0)
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &glyphLineRange,
            withoutAdditionalLayout: true
        )
        let rectInView = lineRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: characterIndex, length: 0))
        let insertionIndex = min(lineRange.location + lineRange.length, string.length)
        hoverInsertionIndex = insertionIndex
        lastInsertionIndex = insertionIndex
        let inset = textContainerInset.width
        let buttonX = max(bounds.width - inset - buttonSize - 2, rectInView.minX)
        let addOrigin = NSPoint(
            x: buttonX,
            y: rectInView.minY + (rectInView.height - buttonSize) / 2
        )
        addButton.frame = NSRect(origin: addOrigin, size: NSSize(width: buttonSize, height: buttonSize))
        addButton.isHidden = false
        updateDoneButton(lineRange: lineRange, rectInView: rectInView, string: string)
    }
}

private final class StateMenuPayload {
    let state: String
    let range: NSRange

    init(state: String, range: NSRange) {
        self.state = state
        self.range = range
    }
}
