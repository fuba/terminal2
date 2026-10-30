import Foundation

public struct KeyChord: Codable, Equatable, Hashable {
    public var key: String
    public var modifiers: [String]
    public init(key: String, modifiers: [String] = []) {
        self.key = key.lowercased(); self.modifiers = Array(Set(modifiers.map { $0.lowercased() })).sorted()
    }
    public static let unbound = KeyChord(key: "")
    public var isEmpty: Bool { key.isEmpty }
    public var normalized: KeyChord { KeyChord(key: key, modifiers: modifiers) }
    public static let validKeys = Set(Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init) +
        ["left", "right", "up", "down", "home", "end", "pageup", "pagedown", "return", "tab", "escape", "space", "delete", "forwarddelete", "grave", "minus", "equal", "leftbracket", "rightbracket", "backslash", "semicolon", "quote", "comma", "period", "slash"] + (1...20).map { "f\($0)" })
    public func validate() throws {
        guard isEmpty || Self.validKeys.contains(key.lowercased()), Set(modifiers).isSubset(of: ["command", "control", "option", "shift"]) else {
            throw TerminalError.message("キーバインドのキーまたは修飾キーが不正です。")
        }
    }
    public var display: String {
        guard !isEmpty else { return "未割り当て" }
        let symbols = ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"]
        let names = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "tab": "⇥", "escape": "Esc", "space": "Space", "delete": "⌫", "forwarddelete": "⌦", "pageup": "⇞", "pagedown": "⇟", "home": "↖", "end": "↘", "grave": "`", "minus": "−", "equal": "=", "leftbracket": "[", "rightbracket": "]", "backslash": "\\", "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/"]
        return ["control", "option", "shift", "command"].filter { modifiers.contains($0) }.map { symbols[$0]! }.joined() + (names[key] ?? key.uppercased())
    }
}

public enum ShortcutContext: CaseIterable { case terminal, search, connections, settings, modal }

public enum ShortcutAction: String, CaseIterable, Identifiable {
    case newTab, closeTab, nextTab, previousTab
    case selectTab1, selectTab2, selectTab3, selectTab4, selectTab5, selectTab6, selectTab7, selectTab8, selectTab9
    case connectionPicker, newSSH, toggleSidebar, find, searchNext, searchPrevious, closeSearch
    case copy, paste, selectAll, copyOrInterrupt, metaLeft, metaRight
    case toggleLog, showLogs, historyUp, historyDown, historyTop, historyBottom, clearHistory
    case zoomIn, zoomOut, resetZoom, showFonts, fitHeight, fullScreen, settings, hideApp, quitApp
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .newTab: return "新しいタブ"
        case .closeTab: return "タブを閉じる"
        case .nextTab: return "次のタブ"
        case .previousTab: return "前のタブ"
        case .connectionPicker: return "接続先を選ぶ…"
        case .newSSH: return "SSH 接続…"
        case .toggleSidebar: return "接続パネルを切り替える"
        case .find: return "検索…"
        case .searchNext: return "次の一致"
        case .searchPrevious: return "前の一致"
        case .closeSearch: return "検索を閉じる"
        case .copy: return "コピー"
        case .paste: return "ペースト"
        case .selectAll: return "すべて選択"
        case .copyOrInterrupt: return "選択をコピー / 割り込み"
        case .metaLeft: return "端末へ Alt＋← を送信"
        case .metaRight: return "端末へ Alt＋→ を送信"
        case .toggleLog: return "セッションログを切り替える"
        case .showLogs: return "ログを表示"
        case .historyUp: return "履歴を上へ"
        case .historyDown: return "履歴を下へ"
        case .historyTop: return "履歴の先頭"
        case .historyBottom: return "履歴の末尾"
        case .clearHistory: return "履歴を消去"
        case .zoomIn: return "拡大"
        case .zoomOut: return "縮小"
        case .resetZoom: return "実際のサイズ"
        case .showFonts: return "フォントを選択…"
        case .fitHeight: return "画面の高さに合わせる"
        case .fullScreen: return "フルスクリーン"
        case .settings: return "設定…"
        case .hideApp: return "Terminal2 を隠す"
        case .quitApp: return "Terminal2 を終了"
        default: return "タブ \(tabIndex! + 1) を選択"
        }
    }
    public var tabIndex: Int? {
        guard rawValue.hasPrefix("selectTab"), let number = Int(rawValue.dropFirst(9)) else { return nil }
        return number - 1
    }
    public var defaultBinding: KeyChord {
        if let index = tabIndex { return KeyChord(key: String(index + 1), modifiers: ["command"]) }
        switch self {
        case .newTab: return KeyChord(key: "t", modifiers: ["command"])
        case .closeTab: return KeyChord(key: "w", modifiers: ["command"])
        case .nextTab: return KeyChord(key: "right", modifiers: ["command"])
        case .previousTab: return KeyChord(key: "left", modifiers: ["command"])
        case .connectionPicker: return KeyChord(key: "k", modifiers: ["command"])
        case .newSSH: return KeyChord(key: "s", modifiers: ["command", "shift"])
        case .toggleSidebar: return KeyChord(key: "l", modifiers: ["command", "shift"])
        case .find: return KeyChord(key: "f", modifiers: ["command"])
        case .searchNext: return KeyChord(key: "return")
        case .searchPrevious: return KeyChord(key: "return", modifiers: ["shift"])
        case .closeSearch: return KeyChord(key: "escape")
        case .copy: return KeyChord(key: "c", modifiers: ["command"])
        case .paste: return KeyChord(key: "v", modifiers: ["command"])
        case .selectAll: return KeyChord(key: "a", modifiers: ["command"])
        case .copyOrInterrupt: return KeyChord(key: "c", modifiers: ["control"])
        case .metaLeft: return KeyChord(key: "left", modifiers: ["option"])
        case .metaRight: return KeyChord(key: "right", modifiers: ["option"])
        case .toggleLog: return KeyChord(key: "l", modifiers: ["command"])
        case .historyUp: return KeyChord(key: "pageup", modifiers: ["shift"])
        case .historyDown: return KeyChord(key: "pagedown", modifiers: ["shift"])
        case .historyTop: return KeyChord(key: "home", modifiers: ["command"])
        case .historyBottom: return KeyChord(key: "end", modifiers: ["command"])
        case .clearHistory: return KeyChord(key: "k", modifiers: ["command", "shift"])
        case .zoomIn: return KeyChord(key: "equal", modifiers: ["command"])
        case .zoomOut: return KeyChord(key: "minus", modifiers: ["command"])
        case .resetZoom: return KeyChord(key: "0", modifiers: ["command"])
        case .showFonts: return KeyChord(key: "t", modifiers: ["command", "shift"])
        case .fullScreen: return KeyChord(key: "f", modifiers: ["command", "control"])
        case .settings: return KeyChord(key: "comma", modifiers: ["command"])
        case .hideApp: return KeyChord(key: "h", modifiers: ["command"])
        case .quitApp: return KeyChord(key: "q", modifiers: ["command"])
        default: return .unbound
        }
    }
    public func allows(_ context: ShortcutContext) -> Bool {
        switch self {
        case .copy, .paste, .selectAll, .hideApp, .quitApp: return true
        case .settings, .showFonts, .closeTab: return context != .modal
        case .searchNext, .searchPrevious, .closeSearch: return context == .search
        case .copyOrInterrupt, .metaLeft, .metaRight, .historyUp, .historyDown, .historyTop, .historyBottom, .clearHistory: return context == .terminal
        default: return context == .terminal || context == .search || context == .connections
        }
    }
    public var terminalSequence: String? {
        switch self { case .metaLeft: return "\u{1b}[1;3D"; case .metaRight: return "\u{1b}[1;3C"; default: return nil }
    }
}

public extension Configuration {
    func binding(for action: ShortcutAction) -> KeyChord { (keyBindings[action.rawValue] ?? action.defaultBinding).normalized }
    func action(for chord: KeyChord, context: ShortcutContext) -> ShortcutAction? {
        guard !chord.isEmpty else { return nil }
        return ShortcutAction.allCases.first { $0.allows(context) && binding(for: $0) == chord.normalized }
    }
    mutating func assign(_ chord: KeyChord, to action: ShortcutAction) {
        if !chord.isEmpty {
            for other in ShortcutAction.allCases where other != action && binding(for: other) == chord.normalized {
                keyBindings[other.rawValue] = .unbound
            }
            if KeyChord(key: hotkey.key, modifiers: hotkey.modifiers) == chord.normalized { hotkey.enabled = false }
        }
        keyBindings[action.rawValue] = chord.normalized
    }
    mutating func assignGlobal(_ chord: KeyChord, enabled: Bool) {
        hotkey.key = chord.normalized.key; hotkey.modifiers = chord.normalized.modifiers; hotkey.enabled = enabled
        if enabled {
            for action in ShortcutAction.allCases where binding(for: action) == chord.normalized { keyBindings[action.rawValue] = .unbound }
        }
    }
}
