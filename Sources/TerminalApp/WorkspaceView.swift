import SwiftUI
import AppKit
import TerminalCore
import SwiftTerm

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        HSplitView {
            if workspace.sidebarVisible {
                ConnectionSidebar(workspace: workspace)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            }
            VStack(spacing: 0) {
                TabStrip(workspace: workspace)
                if let session = workspace.selected {
                    SessionPane(session: session, workspace: workspace).id(session.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .onChange(of: workspace.sidebarVisible) { _, _ in workspace.focusSelected() }
        .sheet(isPresented: $workspace.showingConnect) { ConnectSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.showingBookmark) { BookmarkSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.showingPicker) { ConnectionPicker(workspace: workspace) }
        .alert("Terminal2", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }
}

struct TabStrip: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 4) {
                        ForEach(Array(workspace.sessions.enumerated()), id: \.element.id) { index, session in
                            TabButton(session: session, number: index + 1, selected: workspace.selectedID == session.id,
                                      select: { workspace.select(session.id) }, close: { workspace.close(session) })
                                .id(session.id)
                        }
                    }
                    .padding(6)
                    .onChange(of: workspace.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
            Menu {
                Button("新しいタブ", systemImage: "plus") { workspace.open() }
                Divider()
                ForEach(workspace.shells, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).lastPathComponent) { workspace.open(.shell(path)) }
                }
                Divider()
                Button("SSH 接続…", systemImage: "network") { workspace.showingConnect = true }
                Button("接続を選ぶ…", systemImage: "list.bullet") { workspace.showingPicker = true }
            } label: { Image(systemName: "chevron.down").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).fixedSize().help("新しいセッション")
                .padding(.trailing, 8)
        }
        .background(.bar)
    }
}

struct TabButton: View {
    @ObservedObject var session: TerminalSession
    let number: Int
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 7) {
                    Image(systemName: session.recording ? "record.circle.fill" : session.target.symbol)
                        .foregroundStyle(session.recording ? .red : (selected ? .primary : .secondary))
                    Text(session.title).lineLimit(2).multilineTextAlignment(.leading)
                    if number < 10 { Text("⌘\(number)").font(.system(size: 11)).foregroundStyle(.tertiary) }
                }.frame(minHeight: 26).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 24) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("タブを閉じる")
                .accessibilityLabel("\(session.title) を閉じる")
        }
        .padding(.leading, 10).padding(.trailing, 3).padding(.vertical, 4)
        .glassEffect(selected ? .regular : .identity, in: .rect(cornerRadius: 8))
        .help(session.title)
        .contextMenu {
            Button("新しいタブで開く") { (NSApp.delegate as? AppDelegate)?.workspace.open(session.target) }
            Button(session.recording ? "ログを停止" : "ログを記録") { session.toggleLog() }
            Divider()
            Button("閉じる", role: .destructive, action: close)
        }
    }
}

struct ConnectionSidebar: View {
    @ObservedObject var workspace: Workspace
    @State private var query = ""
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("接続を検索", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await workspace.refreshDiscovery() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("接続先を再読み込み")
            }.padding(12)
            List {
                let favorites = workspace.targets.filter { workspace.configuration.favorites.contains($0.id) && matches($0.name) }
                if !favorites.isEmpty {
                    Section("お気に入り") { ForEach(unique(favorites)) { row($0, pinned: true) } }
                }
                Section("この Mac") {
                    ForEach(workspace.shells.filter { matches($0) }, id: \.self) { row(.shell($0)) }
                }
                if !workspace.configuration.bookmarks.isEmpty {
                    Section("ブックマーク") {
                        ForEach(workspace.configuration.bookmarks.filter { matches($0.name) }) { bookmark in
                            if let target = bookmarkTarget(bookmark) { row(target) }
                        }
                    }
                }
                Section("SSH") {
                    ForEach(workspace.sshProfiles.filter { matches($0.name) }) { row(.ssh($0)) }
                    Button { workspace.showingConnect = true } label: { Label("接続を追加…", systemImage: "plus") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if !workspace.peers.isEmpty {
                    Section("Tailscale") {
                        ForEach(workspace.peers.filter { matches($0.name) }) { peer in
                            row(.ssh(SSHProfile(name: peer.name, host: peer.host)), online: peer.online)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            if let error = workspace.discoveryError {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary).padding(12).textSelection(.enabled)
            }
            HStack {
                Button { workspace.showingBookmark = true } label: { Label("ブックマーク", systemImage: "bookmark.badge.plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
            }.padding(12)
        }
        .background(.background.opacity(0.55))
    }
    private func unique(_ targets: [LaunchTarget]) -> [LaunchTarget] {
        var seen = Set<String>(); return targets.filter { seen.insert($0.id).inserted }
    }
    private func bookmarkTarget(_ bookmark: Bookmark) -> LaunchTarget? {
        if let command = bookmark.command { return .command(bookmark.name, command) }
        if let name = bookmark.ssh, let profile = workspace.sshProfiles.first(where: { $0.name == name }) { return .ssh(profile) }
        return nil
    }
    private func row(_ target: LaunchTarget, pinned: Bool = false, online: Bool? = nil) -> some View {
        Button { workspace.open(target) } label: {
            HStack(spacing: 9) {
                Image(systemName: pinned ? "star.fill" : target.symbol).foregroundStyle(.secondary).frame(width: 16)
                Text(target.name).lineLimit(nil).multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                if let online { Circle().fill(online ? Color.green : Color.secondary).frame(width: 6, height: 6).accessibilityLabel(online ? "オンライン" : "オフライン") }
            }.padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("新しいタブで開く") { workspace.open(target) }
            Button(workspace.configuration.favorites.contains(target.id) ? "お気に入りから外す" : "お気に入りに追加", systemImage: "star") { workspace.favorite(target) }
        }
    }
}

struct TerminalSurface: NSViewRepresentable {
    let session: TerminalSession
    let configuration: Configuration
    func makeNSView(context: Context) -> NativeTerminalView {
        let view = session.terminal
        view.registerForDraggedTypes([.fileURL])
        DispatchQueue.main.async { session.start(configuration: configuration); view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: NativeTerminalView, context: Context) {}
}

struct SessionPane: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var workspace: Workspace
    var body: some View {
        VStack(spacing: 0) {
            if workspace.showingSearch { SearchBar(session: session, close: { workspace.showingSearch = false; workspace.focusSelected() }) }
            TerminalSurface(session: session, configuration: workspace.configuration)
                .padding(.leading, 10).padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                Image(systemName: session.running ? session.target.symbol : "stop.circle").foregroundStyle(.secondary)
                Text(session.status.isEmpty ? session.directory.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~", options: .anchored) : session.status)
                    .lineLimit(2).textSelection(.enabled)
                Spacer(minLength: 4)
                if !session.running {
                    Button("再接続") { workspace.open(session.target, directory: session.directory); workspace.close(session) }.buttonStyle(.link)
                }
                Button { session.toggleLog() } label: { Image(systemName: session.recording ? "record.circle.fill" : "record.circle").foregroundStyle(session.recording ? Color.red : .secondary) }
                    .buttonStyle(.plain).help(session.recording ? "ログを停止 (⌘L)" : "ログを記録 (⌘L)")
                Text(session.metalActive ? "Metal" : "Core Graphics").foregroundStyle(.tertiary)
                Text("\(session.columns) × \(session.rows)").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 7)
        }
        .onAppear { updateTitle() }
        .onChange(of: session.title) { _, _ in updateTitle() }
        .alert("セッション", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
    }
    private func updateTitle() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        workspace.windowController?.window?.title = session.title + " — Terminal2 · v" + build
    }
}

struct SearchBar: View {
    @ObservedObject var session: TerminalSession
    let close: () -> Void
    @State private var query = ""
    @State private var summary = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("端末内を検索", text: $query).textFieldStyle(.plain).focused($focused)
                .onSubmit { find(backward: false) }
                .onChange(of: query) { _, _ in find(backward: false) }
            Text(summary).foregroundStyle(.secondary).monospacedDigit()
            Button { find(backward: true) } label: { Image(systemName: "chevron.up") }.help("前の一致")
            Button { find(backward: false) } label: { Image(systemName: "chevron.down") }.help("次の一致")
            Button { session.terminal.clearSearch(); close() } label: { Image(systemName: "xmark") }.help("検索を閉じる")
        }
        .buttonStyle(.plain).padding(12).background(.bar)
        .onAppear { focused = true }
        .onExitCommand { session.terminal.clearSearch(); close() }
    }
    private func find(backward: Bool) {
        if query.isEmpty { session.terminal.clearSearch(); summary = ""; return }
        if backward { _ = session.terminal.findPrevious(query) } else { _ = session.terminal.findNext(query) }
        let result = session.terminal.searchMatchSummary(query)
        summary = result.total == 0 ? "一致なし" : "\(result.index) / \(result.total)"
    }
}

struct ConnectSheet: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var name = ""
    @State private var user = ""
    @State private var port = ""
    @State private var identity = ""
    @State private var save = true
    @State private var error = ""
    @FocusState private var hostFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("SSH 接続", systemImage: "network").font(.title2.weight(.semibold))
            Form {
                TextField("ホスト / SSH の別名", text: $host).focused($hostFocused)
                TextField("ユーザー", text: $user)
                TextField("ポート", text: $port).help("空欄なら SSH 設定または 22")
                TextField("秘密鍵のパス", text: $identity)
                Toggle("接続先を保存", isOn: $save)
                if save { TextField("表示名", text: $name) }
            }.textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("接続") { connect() }.keyboardShortcut(.defaultAction).disabled(host.isEmpty)
            }
        }.padding(24).frame(width: 440)
        .onAppear { hostFocused = true }
    }
    private func connect() {
        do {
            if !port.isEmpty && Int(port) == nil { throw TerminalError.message("ポートには数値を指定してください。") }
            let profile = SSHProfile(name: name.isEmpty ? host : name, host: host, user: user.isEmpty ? nil : user, port: Int(port), identityFile: identity.isEmpty ? nil : identity)
            try profile.validate()
            if save { workspace.addProfile(profile, connect: true) } else { workspace.open(.ssh(profile)) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct BookmarkSheet: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""
    @State private var ssh = ""
    @State private var remote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ブックマーク").font(.title2.weight(.semibold))
            Form {
                TextField("名前", text: $name)
                Toggle("SSH 接続", isOn: $remote)
                if remote {
                    Picker("接続先", selection: $ssh) {
                        Text("選択してください").tag("")
                        ForEach(workspace.sshProfiles) { Text($0.name).tag($0.name) }
                    }
                } else { TextField("コマンド", text: $command) }
            }.textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    workspace.configuration.bookmarks.removeAll { $0.name == name }
                    workspace.configuration.bookmarks.append(Bookmark(name: name, command: remote ? nil : command, ssh: remote ? ssh : nil))
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || (remote ? ssh.isEmpty : command.isEmpty))
            }
        }.padding(24).frame(width: 440)
    }
}

struct ConnectionPicker: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var matches: [LaunchTarget] {
        var seen = Set<String>()
        return workspace.targets.filter { seen.insert($0.id).inserted && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("接続先 / シェルを検索", text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let first = matches.first { workspace.open(first); dismiss() } }
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(14)
            List(matches) { target in
                Button { workspace.open(target); dismiss() } label: {
                    Label(target.name, systemImage: target.symbol).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.listStyle(.plain)
        }.frame(width: 500, height: 400).onAppear { focused = true }
    }
}
