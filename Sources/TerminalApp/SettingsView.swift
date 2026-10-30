import SwiftUI
import TerminalCore
import AppKit

struct SettingsView: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        TabView {
            Form {
                Section("文字") {
                    TextField("フォント", text: $workspace.configuration.fontFamily)
                    Stepper("サイズ  \(Int(workspace.configuration.fontSize)) pt", value: $workspace.configuration.fontSize, in: 8...48)
                    ColorPicker("文字色", selection: color(\.foreground), supportsOpacity: false)
                    ColorPicker("背景色", selection: color(\.background), supportsOpacity: false)
                    Toggle("Metal で描画", isOn: $workspace.configuration.useMetal)
                }
                Section("ウィンドウ") {
                    HStack {
                        Text("不透明度")
                        Slider(value: $workspace.configuration.opacity, in: 0.35...1)
                        Text("\(Int(workspace.configuration.opacity * 100))%").monospacedDigit().frame(width: 42)
                    }
                    Stepper("列  \(workspace.configuration.columns)", value: $workspace.configuration.columns, in: 40...500)
                    Stepper("行  \(workspace.configuration.rows)", value: $workspace.configuration.rows, in: 10...200)
                    Button("ウィンドウを指定サイズに合わせる") { workspace.windowController?.resizeToGrid() }
                }
                Section("履歴") {
                    Stepper("\(workspace.configuration.scrollback) 行", value: $workspace.configuration.scrollback, in: 1000...100000, step: 1000)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("外観", systemImage: "textformat") }

            Form {
                Section("シェル") {
                    Picker("標準シェル", selection: $workspace.configuration.shell) {
                        ForEach(Array(Set(workspace.shells + [workspace.configuration.shell])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Option を Meta として送信", isOn: $workspace.configuration.optionAsMeta)
                }
                Section("グローバルホットキー") {
                    Toggle("ウィンドウを表示 / 非表示", isOn: $workspace.configuration.hotkey.enabled)
                    HStack {
                        ForEach(["control", "option", "shift", "command"], id: \.self) { modifier in
                            Toggle(symbol(modifier), isOn: modifierBinding(modifier)).toggleStyle(.button)
                        }
                        Picker("キー", selection: $workspace.configuration.hotkey.key) {
                            ForEach(Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init) + ["grave", "space", "tab"] + (1...12).map { "f\($0)" }, id: \.self) { Text($0.uppercased()).tag($0) }
                        }.labelsHidden().frame(width: 95)
                    }
                }
                Section("ショートカット") {
                    shortcut("新しいタブ / 閉じる", "⌘T / ⌘W")
                    shortcut("接続先を選ぶ / SSH 接続", "⌘K / ⌘⇧S")
                    shortcut("次 / 前のタブ", "⌘⇧] / ⌘⇧[")
                    shortcut("検索 / ログ", "⌘F / ⌘L")
                    shortcut("画面の高さに合わせる", "F11")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("操作", systemImage: "keyboard") }

            Form {
                Section("SSH 接続先") {
                    ForEach(workspace.configuration.sshProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                Text(profile.destination).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Button("削除", role: .destructive) { workspace.configuration.sshProfiles.removeAll { $0.id == profile.id } }
                        }
                    }
                    Button("追加…") { workspace.showingConnect = true; workspace.windowController?.showWindow(nil) }
                    Text("~/.ssh/config の接続先も自動で読み込みます。").foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !workspace.configuration.bookmarks.isEmpty {
                    Section("ブックマーク") {
                        ForEach(workspace.configuration.bookmarks) { bookmark in
                            HStack {
                                Text(bookmark.name); Spacer()
                                Button("削除", role: .destructive) { workspace.configuration.bookmarks.removeAll { $0.id == bookmark.id } }
                            }
                        }
                    }
                }
                Section("ファイル") {
                    Button("設定ファイルを開く…") { NSWorkspace.shared.open(AppPaths.config) }
                    Button("ログフォルダを開く…") { NSWorkspace.shared.open(AppPaths.logs) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("接続", systemImage: "network") }
        }
        .frame(width: 580, height: 620)
        .padding(8)
    }
    private func shortcut(_ title: String, _ key: String) -> some View {
        HStack { Text(title); Spacer(); Text(key).foregroundStyle(.secondary).monospaced() }
    }
    private func symbol(_ value: String) -> String {
        ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"][value] ?? value
    }
    private func modifierBinding(_ modifier: String) -> Binding<Bool> {
        Binding(get: { workspace.configuration.hotkey.modifiers.contains(modifier) }, set: { enabled in
            var modifiers = workspace.configuration.hotkey.modifiers
            if enabled { modifiers.append(modifier) } else { modifiers.removeAll { $0 == modifier } }
            workspace.configuration.hotkey.modifiers = modifiers
        })
    }
    private func color(_ path: WritableKeyPath<Configuration, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: workspace.configuration[keyPath: path])) }, set: {
            workspace.configuration[keyPath: path] = NSColor($0).hex
        })
    }
}
