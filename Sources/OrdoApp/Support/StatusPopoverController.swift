import AppKit
import SwiftUI

final class StatusPopoverController {
    private let popover: NSPopover
    private var eventMonitor: Any?

    init(rootView: ContentView) {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func toggle(relativeTo positioningRect: NSRect, of view: NSView?) {
        if popover.isShown {
            hide()
        } else {
            show(relativeTo: positioningRect, of: view)
        }
    }

    func show(relativeTo positioningRect: NSRect, of view: NSView?) {
        guard let view else { return }
        popover.show(relativeTo: positioningRect, of: view, preferredEdge: .minY)
        startMonitoringEvents()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        popover.performClose(nil)
        stopMonitoringEvents()
    }

    private func startMonitoringEvents() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func stopMonitoringEvents() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
