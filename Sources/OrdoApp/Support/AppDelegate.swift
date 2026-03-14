import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var document: OrdoDocument?
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    var settings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        disablePressAndHold()
        let settings = resolvedSettings()
        document = OrdoDocument(fileURL: settings.orgFileURL)
        NSApp.setActivationPolicy(.accessory)
        guard let document else { return }
        let rootView = AnyView(ContentView(document: document, settings: settings))
        panelController = FloatingPanelController(rootView: rootView, settings: settings)
        panelController?.show()
        configureStatusItem()
        observeSpaceChanges()
        observeSettingsChanges(settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func resolvedSettings() -> AppSettings {
        if let settings {
            return settings
        }
        let newSettings = AppSettings()
        settings = newSettings
        return newSettings
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

    private func observeSettingsChanges(_ settings: AppSettings) {
        settings.$orgFilePath
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadDocument()
            }
            .store(in: &cancellables)
    }

    private func reloadDocument() {
        guard let settings else { return }
        let newDocument = OrdoDocument(fileURL: settings.orgFileURL)
        document = newDocument
        let rootView = AnyView(ContentView(document: newDocument, settings: settings))
        if let panelController {
            panelController.updateRootView(rootView)
        } else {
            panelController = FloatingPanelController(rootView: rootView, settings: settings)
            panelController?.show()
        }
    }

    private func disablePressAndHold() {
        let key = "ApplePressAndHoldEnabled" as CFString
        CFPreferencesSetAppValue(key, kCFBooleanFalse, kCFPreferencesCurrentApplication)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}
