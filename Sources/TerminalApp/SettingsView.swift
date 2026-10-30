import SwiftUI
import TerminalCore
import AppKit

struct SettingsView: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        TabView {
            Form {
                Section("文字") {
                    HStack {
                        Button("フォントを選択…") { (NSApp.delegate as? AppDelegate)?.showFonts() }
                        Spacer()
                        Text(fontDescription).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    Picker("配色", selection: themeBinding) {
                        ForEach(TerminalTheme.all) { Text($0.name).tag($0.id) }
                        Text("カスタム").tag("custom")
                    }
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
                        ForEach(Array(Set(workspace.availableShells + workspace.shells + [workspace.configuration.shell])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Option を Meta として送信", isOn: $workspace.configuration.optionAsMeta)
                }
                Section("シェル一覧") {
                    ForEach(workspace.configuration.localShells, id: \.self) { path in
                        HStack {
                            Text(path).textSelection(.enabled); Spacer()
                            Button("削除") { workspace.configuration.localShells.removeAll { $0 == path } }
                        }
                    }
                    Button("シェルを追加…") { workspace.addShell() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("操作", systemImage: "keyboard") }

            KeyboardSettings(workspace: workspace)
                .tabItem { Label("キー割り当て", systemImage: "command") }

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
                    Button("設定ファイルを開く…") { NSWorkspace.shared.open(workspace.configurationURL) }
                    Button("ログフォルダを開く…") { NSWorkspace.shared.open(AppPaths.logs) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("接続", systemImage: "network") }
        }
        .frame(width: 650, height: 660)
        .padding(8)
    }
    private var fontDescription: String {
        let font = NSFont(name: workspace.configuration.fontFamily, size: workspace.configuration.fontSize)
        return "\(font?.displayName ?? workspace.configuration.fontFamily)  \(Int(workspace.configuration.fontSize)) pt"
    }
    private var themeBinding: Binding<String> {
        Binding(get: { TerminalTheme.matching(workspace.configuration)?.id ?? "custom" }, set: { id in
            guard let theme = TerminalTheme.all.first(where: { $0.id == id }) else { return }
            var config = workspace.configuration; theme.apply(to: &config); workspace.configuration = config
        })
    }
    private func color(_ path: WritableKeyPath<Configuration, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: workspace.configuration[keyPath: path])) }, set: {
            workspace.configuration[keyPath: path] = NSColor($0).hex
        })
    }
}

struct KeyboardSettings: View {
    @ObservedObject var workspace: Workspace
    @State private var query = ""
    var body: some View {
        VStack(spacing: 0) {
            TextField("操作を検索", text: $query).textFieldStyle(.roundedBorder).padding(12)
            Form {
                Section("グローバルホットキー") {
                    HStack {
                        Toggle("表示 / 非表示", isOn: Binding(get: { workspace.configuration.hotkey.enabled }, set: { enabled in
                            var config = workspace.configuration
                            config.assignGlobal(KeyChord(key: config.hotkey.key, modifiers: config.hotkey.modifiers), enabled: enabled)
                            workspace.configuration = config
                        }))
                        ShortcutRecorder(binding: KeyChord(key: workspace.configuration.hotkey.key, modifiers: workspace.configuration.hotkey.modifiers), requiresModifier: true) { chord in
                            var config = workspace.configuration
                            config.assignGlobal(chord, enabled: config.hotkey.enabled)
                            workspace.configuration = config
                        }.frame(width: 165)
                    }
                }
                Section("アプリと端末") {
                    ForEach(ShortcutAction.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { action in
                        HStack(spacing: 8) {
                            Text(action.title).lineLimit(nil)
                            Spacer(minLength: 8)
                            ShortcutRecorder(binding: workspace.configuration.binding(for: action)) { workspace.assignShortcut($0, to: action) }
                                .frame(width: 165)
                            Button { workspace.assignShortcut(.unbound, to: action) } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("割り当てを解除")
                        }
                    }
                }
                Section {
                    Button("キー割り当てを既定値に戻す") {
                        var config = workspace.configuration; config.keyBindings = [:]; config.hotkey = HotkeyConfiguration(); workspace.configuration = config
                    }
                }
            }.formStyle(.grouped)
        }
    }
}
