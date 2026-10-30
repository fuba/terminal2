import AppKit
import Combine
import TerminalCore

@MainActor
final class Workspace: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: UUID?
    @Published var configuration = Configuration() {
        didSet { configurationChanged() }
    }
    @Published var sshProfiles: [SSHProfile] = []
    @Published var peers: [TailscalePeer] = []
    @Published var discoveryError: String?
    @Published var sidebarVisible = false {
        didSet { windowController?.setSidebarVisible(sidebarVisible) }
    }
    @Published var showingConnect = false
    @Published var showingBookmark = false
    @Published var showingPicker = false
    @Published var showingSearch = false
    @Published var error: String?
    let availableShells = Shell.available()
    var shells: [String] { configuration.localShells.filter { FileManager.default.isExecutableFile(atPath: $0) } }
    var searchHandler: ((Bool) -> Void)?
    weak var windowController: TerminalWindowController?
    var onConfigurationChanged: (() -> Void)?
    private var configurationData: Data?
    private var watchTimer: Timer?
    private var applyingExternal = false
    private var refreshing = false
    let configurationURL: URL

    var selected: TerminalSession? { sessions.first { $0.id == selectedID } }
    var targets: [LaunchTarget] {
        shells.map(LaunchTarget.shell) + configuration.bookmarks.compactMap { bookmark in
            if let command = bookmark.command { return .command(bookmark.name, command) }
            if let name = bookmark.ssh, let profile = sshProfiles.first(where: { $0.name == name }) { return .ssh(profile) }
            return nil
        } + sshProfiles.map(LaunchTarget.ssh) + peers.map { .ssh(SSHProfile(name: $0.name, host: $0.host)) }
    }

    init(configurationURL: URL = AppPaths.config) {
        self.configurationURL = configurationURL
        do {
            try AppPaths.prepare()
            configuration = try AppPaths.load(from: configurationURL)
            if !FileManager.default.fileExists(atPath: configurationURL.path) { try AppPaths.save(configuration, to: configurationURL) }
            configurationData = try Data(contentsOf: configurationURL)
        } catch { self.error = "設定を読み込めませんでした。\n" + error.localizedDescription }
        reloadSSH()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadConfiguration() }
        }
        Task { await refreshDiscovery() }
    }

    private func configurationChanged() {
        do {
            _ = try configuration.validated()
            if !applyingExternal {
                try AppPaths.save(configuration, to: configurationURL)
                configurationData = try Data(contentsOf: configurationURL)
            }
            sessions.forEach { $0.apply(configuration) }
            reloadSSH()
            windowController?.applyAppearance()
            onConfigurationChanged?()
        } catch { self.error = error.localizedDescription }
    }
    func reloadConfiguration() {
        guard let data = try? Data(contentsOf: configurationURL), data != configurationData else { return }
        configurationData = data
        do {
            let next = try AppPaths.load(from: configurationURL)
            applyingExternal = true
            configuration = next
            applyingExternal = false
            Diagnostics.log("Configuration reloaded")
        } catch { self.error = "設定の変更を適用できませんでした。\n" + error.localizedDescription }
    }
    func reloadSSH() {
        let aliases = SSHConfigDiscovery.aliases()
        let explicitNames = Set(configuration.sshProfiles.map(\.name))
        sshProfiles = configuration.sshProfiles + aliases.filter { !explicitNames.contains($0) }.map { SSHProfile(name: $0, host: $0) }
        sshProfiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func refreshDiscovery() async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        reloadSSH()
        do { peers = try await TailscalePeer.discover(); discoveryError = nil }
        catch { discoveryError = error.localizedDescription; Diagnostics.log("Tailscale discovery: \(error)") }
    }
    func open(_ target: LaunchTarget? = nil, directory: String? = nil) {
        let target = target ?? .shell(configuration.shell)
        var cwd = directory
        if cwd == nil, let selected, case .ssh = selected.target {} else if cwd == nil { cwd = selected?.directory }
        if let candidate = cwd, !FileManager.default.fileExists(atPath: candidate) { cwd = nil }
        let session = TerminalSession(target: target, configuration: configuration, directory: cwd)
        sessions.append(session); selectedID = session.id
        focusSelected()
    }
    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        session.close(); sessions.remove(at: index)
        if selectedID == session.id { selectedID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id }
        if sessions.isEmpty { open() }
        focusSelected()
    }
    func select(_ id: UUID) { selectedID = id; focusSelected() }
    func cycle(_ delta: Int) {
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.id == selectedID } ?? 0
        select(sessions[(index + delta + sessions.count) % sessions.count].id)
    }
    func focusSelected() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let terminal = self.selected?.terminal else { return }
            self.windowController?.window?.makeFirstResponder(terminal)
        }
    }
    func favorite(_ target: LaunchTarget) {
        if configuration.favorites.contains(target.id) { configuration.favorites.removeAll { $0 == target.id } }
        else { configuration.favorites.append(target.id) }
    }
    func addProfile(_ profile: SSHProfile, connect: Bool) {
        do {
            try profile.validate()
            configuration.sshProfiles.removeAll { $0.name == profile.name }
            configuration.sshProfiles.append(profile)
            if connect { open(.ssh(profile)) }
        } catch { self.error = error.localizedDescription }
    }
    func assignShortcut(_ chord: KeyChord, to action: ShortcutAction) {
        var config = configuration
        config.assign(chord, to: action)
        configuration = config
    }
    func addShell() {
        let panel = NSOpenPanel()
        panel.title = "シェルを追加"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "実行可能なシェルを選択してください。"; return }
        if !configuration.localShells.contains(url.path) { configuration.localShells.append(url.path) }
    }
    func shutdown() { watchTimer?.invalidate(); sessions.forEach { $0.close() } }
}
