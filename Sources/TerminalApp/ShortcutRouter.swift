import AppKit
import SwiftUI
import Carbon
import TerminalCore

enum ShortcutRouter {
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29,
        "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41, "backslash": 42, "comma": 43,
        "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48, "space": 49, "grave": 50,
        "delete": 51, "escape": 53, "f17": 64, "f18": 79, "f19": 80, "f20": 90, "f5": 96, "f6": 97,
        "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103, "f13": 105, "f16": 106, "f14": 107,
        "f10": 109, "f12": 111, "f15": 113, "home": 115, "pageup": 116, "forwarddelete": 117,
        "f4": 118, "end": 119, "f2": 120, "pagedown": 121, "f1": 122, "left": 123, "right": 124, "down": 125, "up": 126
    ]
    static func modifiers(_ chord: KeyChord) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if chord.modifiers.contains("command") { result.insert(.command) }
        if chord.modifiers.contains("control") { result.insert(.control) }
        if chord.modifiers.contains("option") { result.insert(.option) }
        if chord.modifiers.contains("shift") { result.insert(.shift) }
        return result
    }
    static func chord(for event: NSEvent) -> KeyChord? {
        guard let key = keyCodes.first(where: { $0.value == event.keyCode })?.key else { return nil }
        let flags = event.modifierFlags
        var modifiers: [String] = []
        if flags.contains(.command) { modifiers.append("command") }
        if flags.contains(.control) { modifiers.append("control") }
        if flags.contains(.option) { modifiers.append("option") }
        if flags.contains(.shift) { modifiers.append("shift") }
        return KeyChord(key: key, modifiers: modifiers)
    }
    static func action(for event: NSEvent, configuration: Configuration, context: ShortcutContext) -> ShortcutAction? {
        guard event.type == .keyDown, let chord = chord(for: event) else { return nil }
        return configuration.action(for: chord, context: context)
    }
    static func menuEquivalent(_ chord: KeyChord) -> String {
        guard !chord.isEmpty else { return "" }
        let named: [String: Int] = ["left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey, "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey, "home": NSHomeFunctionKey, "end": NSEndFunctionKey, "pageup": NSPageUpFunctionKey, "pagedown": NSPageDownFunctionKey, "forwarddelete": NSDeleteFunctionKey]
        if let code = named[chord.key], let scalar = UnicodeScalar(code) { return String(scalar) }
        if chord.key.hasPrefix("f"), let number = Int(chord.key.dropFirst()), (1...20).contains(number) {
            return String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
        }
        let characters = ["return": "\r", "tab": "\t", "escape": "\u{1b}", "space": " ", "delete": "\u{7f}", "grave": "`", "minus": "-", "equal": "=", "leftbracket": "[", "rightbracket": "]", "backslash": "\\", "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/"]
        return characters[chord.key] ?? chord.key
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let binding: KeyChord
    var requiresModifier = false
    let onChange: (KeyChord) -> Void
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        button.target = button; button.action = #selector(ShortcutRecorderButton.beginRecording)
        button.onChange = onChange; button.chord = binding; button.requiresModifier = requiresModifier
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange; button.chord = binding; button.requiresModifier = requiresModifier
        if !button.recording { button.title = binding.display }
    }
}

final class ShortcutRecorderButton: NSButton {
    var chord = KeyChord.unbound { didSet { if !recording { title = chord.display } } }
    var onChange: ((KeyChord) -> Void)?
    private(set) var recording = false
    var requiresModifier = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        if recording { stopRecording(); return }
        recording = true; title = "キーを押してください"
        toolTip = "もう一度クリックすると記録を中止します。"
        window?.makeFirstResponder(self)
        (NSApp.delegate as? AppDelegate)?.setRecordingShortcut(true)
    }
    func capture(_ event: NSEvent) {
        guard recording else { return }
        guard let chord = ShortcutRouter.chord(for: event) else { NSSound.beep(); return }
        if requiresModifier && chord.modifiers.isEmpty { title = "修飾キーが必要です"; NSSound.beep(); return }
        stopRecording()
        onChange?(chord)
    }
    func stopRecording() {
        guard recording else { return }
        recording = false; title = chord.display
        toolTip = "クリックしてキーを変更します。"
        (NSApp.delegate as? AppDelegate)?.setRecordingShortcut(false)
    }
    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}
