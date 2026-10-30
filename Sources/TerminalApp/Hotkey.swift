import AppKit
import Carbon
import TerminalCore

@MainActor
final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var keyCode: UInt16?
    private var eventModifiers: NSEvent.ModifierFlags = []
    var onPress: (() -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<GlobalHotkey>.fromOpaque(data).takeUnretainedValue().onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ configuration: HotkeyConfiguration) throws {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        keyCode = nil; eventModifiers = []
        guard configuration.enabled else { return }
        guard let key = ShortcutRouter.keyCodes[configuration.key.lowercased()] else { throw TerminalError.message("ホットキーのキーが不正です。") }
        var flags: UInt32 = 0
        for modifier in configuration.modifiers {
            switch modifier {
            case "command": flags |= UInt32(cmdKey); eventModifiers.insert(.command)
            case "option": flags |= UInt32(optionKey); eventModifiers.insert(.option)
            case "shift": flags |= UInt32(shiftKey); eventModifiers.insert(.shift)
            case "control": flags |= UInt32(controlKey); eventModifiers.insert(.control)
            default: throw TerminalError.message("ホットキーの修飾キーが不正です: \(modifier)")
            }
        }
        guard flags != 0 else { throw TerminalError.message("ホットキーには修飾キーが必要です。") }
        let status = RegisterEventHotKey(UInt32(key), flags, EventHotKeyID(signature: 0x54324d41, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw TerminalError.message("ホットキーを登録できませんでした (\(status))。別のキーを設定してください。") }
        keyCode = UInt16(key)
    }
    func matches(_ event: NSEvent) -> Bool {
        reference != nil && event.type == .keyDown && !event.isARepeat && event.keyCode == keyCode &&
        event.modifierFlags.intersection([.control, .option, .shift, .command]) == eventModifiers
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
