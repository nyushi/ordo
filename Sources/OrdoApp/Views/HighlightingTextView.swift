import Foundation
import SwiftUI

struct HighlightingTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = OrgTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = Self.baseFont
        textView.textColor = .labelColor
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.backgroundColor = .clear
        textView.insertionPointColor = .controlAccentColor
        context.coordinator.textView = textView

        scrollView.documentView = textView
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
}
