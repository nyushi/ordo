import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private let signature: OSType = 0x6f72646f // 'ordo'

    private init() {
        installHandlerIfNeeded()
    }

    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister()
        self.handler = handler

        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            carbonFlags(from: modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        guard status == noErr else {
            NSLog("Ordo: failed to register hotkey (\(status))")
            return
        }
        hotKeyRef = hotKey
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        handler = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard
                    let userData,
                    let eventRef
                else {
                    return OSStatus(eventNotHandledErr)
                }
                let instance = Unmanaged<GlobalHotKeyCenter>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return instance.handleHotKey(eventRef: eventRef)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        if status != noErr {
            NSLog("Ordo: failed to install hotkey handler (\(status))")
        }
    }

    private func handleHotKey(eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }
        handler?()
        return noErr
    }

    private func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
