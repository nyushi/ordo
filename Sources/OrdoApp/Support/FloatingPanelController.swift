import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingPanelController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView, settings: AppSettings) {
        let contentRect = NSRect(x: 200, y: 200, width: 420, height: 520)
        let panel = FloatingPanel(contentRect: contentRect, settings: settings)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let containerView = RoundedPanelContainerView()
        panel.contentView = containerView
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        self.hostingView = hostingView
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

    func updateRootView(_ view: AnyView) {
        hostingView.rootView = view
    }
}

@MainActor
private final class FloatingPanel: NSPanel {
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var inactiveAlpha: CGFloat
    private var focusAlpha: CGFloat
    private var transparencyCancellable: AnyCancellable?
    private let settings: AppSettings

    init(contentRect: NSRect, settings: AppSettings) {
        self.settings = settings
        inactiveAlpha = CGFloat(settings.inactiveTransparency)
        focusAlpha = CGFloat(settings.focusedTransparency)
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
        // IMPORTANT: This panel must remain non-activating + status bar level so that
        // Aerospace などの WM に通常ウィンドウとして認識されない。
        // style/level/collectionBehavior を変更すると常時表示要件が壊れるため注意。
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] // keep synced with README note
        minSize = NSSize(width: 340, height: 280)
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        alphaValue = inactiveAlpha
        acceptsMouseMovedEvents = true
        observeTransparencyChanges()
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
        let isKey = isKeyWindow
        let shouldFocus = isPointerInside || isKey
        let target = shouldFocus ? focusAlpha : inactiveAlpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.animator().alphaValue = target
        }
    }

    private func observeTransparencyChanges() {
        transparencyCancellable = settings.$inactiveTransparency
            .combineLatest(settings.$focusedTransparency)
            .sink { [weak self] inactive, focused in
                self?.applyTransparency(inactive: inactive, focused: focused)
            }
    }

    private func applyTransparency(inactive: Double, focused: Double) {
        inactiveAlpha = CGFloat(inactive)
        focusAlpha = CGFloat(focused)
        updateTransparency()
    }
}

private final class RoundedPanelContainerView: NSView {
    private let cornerRadius: CGFloat = 18
    private let fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = fillColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius
    }
}
