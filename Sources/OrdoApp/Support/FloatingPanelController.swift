import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSWindowController {
    init(rootView: ContentView) {
        let contentRect = NSRect(x: 200, y: 200, width: 420, height: 520)
        let panel = FloatingPanel(contentRect: contentRect)
        panel.contentView = NSHostingView(rootView: rootView)
        super.init(window: panel)
        window?.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggleVisibility() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class FloatingPanel: NSPanel {
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private let inactiveAlpha: CGFloat = 0.32
    private let focusAlpha: CGFloat = 0.96

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .fullSizeContentView,
                .resizable
            ],
            backing: .buffered,
            defer: false)
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        minSize = NSSize(width: 340, height: 280)
        level = .statusBar
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9)
        isOpaque = false
        hasShadow = true
        alphaValue = inactiveAlpha
        acceptsMouseMovedEvents = true
    }

    override var contentView: NSView? {
        didSet {
            if let oldView = oldValue, let trackingArea {
                oldView.removeTrackingArea(trackingArea)
            }
            installTrackingArea()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        updateTransparency()
    }

    override func resignKey() {
        super.resignKey()
        updateTransparency()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
        updateTransparency()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
        updateTransparency()
    }

    private func installTrackingArea() {
        guard let contentView else { return }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    private func updateTransparency() {
        let target = isPointerInside ? focusAlpha : inactiveAlpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.animator().alphaValue = target
        }
    }
}
