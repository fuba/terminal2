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
        let keys: [String: Int] = ["a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "grave": kVK_ANSI_Grave, "space": kVK_Space, "tab": kVK_Tab, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12]
        guard let key = keys[configuration.key.lowercased()] else { throw TerminalError.message("ホットキーのキーが不正です。") }
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
