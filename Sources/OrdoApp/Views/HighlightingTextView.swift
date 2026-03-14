import Foundation
import SwiftUI

struct HighlightingTextView: NSViewRepresentable {
    @Binding var text: String
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
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.backgroundColor = NSColor.clear
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.onInsertTodo = { [weak coordinator = context.coordinator] index in
            coordinator?.insertTodo(at: index)
        }
        textView.string = text
        context.coordinator.textView = textView
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
    }
}

extension HighlightingTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextView
        weak var textView: NSTextView?
        var isUpdatingFromModel = false

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

            content.enumerateSubstrings(in: fullRange, options: .byLines) { substring, range, _, _ in
                guard let line = substring else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("*") {
                    textStorage.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.systemBlue
                    ], range: range)
                }

                if trimmed.contains(" TODO") || trimmed.hasPrefix("TODO") || trimmed.contains("TODO ") {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.systemOrange,
                        .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.18)
                    ], range: range)
                } else if trimmed.contains(" DONE") || trimmed.hasPrefix("DONE") {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.systemGreen.withAlphaComponent(0.9),
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ], range: range)
                }
            }

            textStorage.endEditing()
        }
        
        func insertTodo(at index: Int) {
            guard let textView else { return }
            let caretIndex = parent.onInsertTodo(index, textView.undoManager)
            guard let caretIndex else { return }
            let range = NSRange(location: caretIndex, length: 0)
            DispatchQueue.main.async { [weak textView] in
                textView?.setSelectedRange(range)
                textView?.scrollRangeToVisible(range)
            }
        }
    }

    static var baseFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }
}

private final class OrgTextView: NSTextView {
    private static let keywordRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[*-]+\s+)?(TODO|DONE)\b"#,
        options: []
    )
    
    var onInsertTodo: ((Int) -> Void)?
    private var addButton: NSButton = {
        let image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add TODO")!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.isHidden = true
        button.alphaValue = 0.85
        button.contentTintColor = .systemOrange
        return button
    }()
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverInsertionIndex: Int?
    private let buttonSize: CGFloat = 18
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        addSubview(addButton)
        addButton.target = self
        addButton.action = #selector(insertTodoFromButton)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
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
        var toggled = false
        if event.clickCount == 1 {
            toggled = toggleKeywordIfNeeded(event: event)
        }
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        if toggled {
            didChangeText()
        }
    }

    override var acceptsFirstResponder: Bool { true }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateAddButtonPosition(for: event)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateAddButtonPosition(for: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideAddButton()
    }

    private func toggleKeywordIfNeeded(event: NSEvent) -> Bool {
        guard
            let layoutManager,
            let textContainer,
            let textStorage
        else { return false }

        var location = convert(event.locationInWindow, from: nil)
        location.x -= textContainerOrigin.x
        location.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        if glyphIndex >= layoutManager.numberOfGlyphs { return false }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard
            let rangeInfo = keywordRange(containing: characterIndex, in: textStorage.string as NSString)
        else { return false }

        let (keywordRange, keyword) = rangeInfo
        guard NSLocationInRange(characterIndex, keywordRange) else { return false }

        let replacement = (keyword == "TODO") ? "DONE" : "TODO"
        textStorage.replaceCharacters(in: keywordRange, with: replacement)
        return true
    }

    private func keywordRange(containing index: Int, in string: NSString) -> (NSRange, String)? {
        guard string.length > 0, index < string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
        let lineString = string.substring(with: lineRange) as NSString
        guard
            let match = Self.keywordRegex.firstMatch(
                in: lineString as String,
                options: [],
                range: NSRange(location: 0, length: lineString.length)
            )
        else { return nil }

        let keywordRangeInLine = match.range(at: 1)
        guard keywordRangeInLine.location != NSNotFound else { return nil }

        let keywordRange = NSRange(
            location: lineRange.location + keywordRangeInLine.location,
            length: keywordRangeInLine.length
        )
        let keyword = string.substring(with: keywordRange)
        return (keywordRange, keyword)
    }
    
    private func updateAddButtonPosition(for event: NSEvent) {
        guard
            let layoutManager,
            let textContainer,
            let textStorage
        else {
            hideAddButton()
            return
        }
        
        var location = convert(event.locationInWindow, from: nil)
        let buttonGuardX = bounds.width - textContainerInset.width - buttonSize - 4
        if location.x >= buttonGuardX, hoverInsertionIndex != nil {
            // マウスがボタン付近に入った際は位置・行情報を固定する
            return
        }

        location.x -= textContainerOrigin.x
        location.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        if glyphIndex >= layoutManager.numberOfGlyphs {
            hideAddButton()
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
        hoverInsertionIndex = min(lineRange.location + lineRange.length, string.length)
        let inset = textContainerInset.width
        // すべての行で右端の同じ位置にボタンを並べ、視覚的なブレをなくす
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
        hoverInsertionIndex = nil
    }
    
    @objc private func insertTodoFromButton() {
        guard let index = hoverInsertionIndex else { return }
        onInsertTodo?(index)
        hideAddButton()
    }
}
