import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let document = OrdoDocument()
    private var popoverController: StatusPopoverController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let rootView = ContentView(document: document)
        popoverController = StatusPopoverController(rootView: rootView)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Ordo")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        configureGlobalHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyCenter.shared.unregister()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard
            let button = statusItem?.button,
            let popoverController
        else { return }
        popoverController.toggle(relativeTo: button.bounds, of: button)
    }

    private func configureGlobalHotKey() {
        GlobalHotKeyCenter.shared.register(
            keyCode: UInt32(kVK_Space),
            modifiers: [.command, .option]) { [weak self] in
                guard
                    let self,
                    let button = self.statusItem?.button
                else { return }
                self.popoverController?.toggle(relativeTo: button.bounds, of: button)
            }
    }
}
