import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private let document = OrdoDocument()
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let rootView = ContentView(document: document)
        panelController = FloatingPanelController(rootView: rootView)
        panelController?.show()
        configureStatusItem()
        configureGlobalHotKey()
        observeSpaceChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyCenter.shared.unregister()
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Ordo")
        button.target = self
        button.action = #selector(toggleFromStatusItem)
    }

    @objc
    private func toggleFromStatusItem() {
        panelController?.toggleVisibility()
    }

    private func configureGlobalHotKey() {
        GlobalHotKeyCenter.shared.register(
            keyCode: UInt32(kVK_Space),
            modifiers: [.command, .option]) { [weak self] in
                self?.panelController?.toggleVisibility()
            }
    }

    private func observeSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelController?.show()
            }
        }
    }
}
