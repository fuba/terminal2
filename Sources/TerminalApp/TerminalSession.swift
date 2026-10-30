import AppKit
import SwiftTerm
import TerminalCore
import Combine

enum LaunchTarget: Identifiable, Equatable {
    case shell(String)
    case command(String, String)
    case ssh(SSHProfile)
    var id: String {
        switch self {
        case .shell(let path): return "shell:" + path
        case .command(let name, _): return "bookmark:" + name
        case .ssh(let profile): return profile.id
        }
    }
    var name: String {
        switch self {
        case .shell(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .command(let name, _): return name
        case .ssh(let profile): return profile.name
        }
    }
    var symbol: String { if case .ssh = self { return "network" }; return "terminal" }
}

/// LocalProcess delivers all callbacks on the main queue; window-size reads may occur off-queue.
private final class ProcessBridge: LocalProcessDelegate {
    weak var session: TerminalSession?
    private let lock = NSLock()
    private var size = winsize(ws_row: 32, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
    func updateSize(cols: Int, rows: Int, pixels: CGSize) {
        lock.lock(); defer { lock.unlock() }
        size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: UInt16(clamping: Int(pixels.width)), ws_ypixel: UInt16(clamping: Int(pixels.height)))
    }
    func getWindowSize() -> winsize { lock.lock(); defer { lock.unlock() }; return size }
    func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { session?.receive(Data(slice)) }
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        MainActor.assumeIsolated { session?.didExit(exitCode) }
    }
    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
        MainActor.assumeIsolated { session?.failed(error.localizedDescription) }
    }
}

@MainActor
final class TerminalSession: NSObject, ObservableObject, Identifiable, TerminalViewDelegate {
    let id = UUID()
    let target: LaunchTarget
    let terminal: NativeTerminalView
    @Published var title: String
    @Published var directory: String
    @Published var running = false
    @Published var recording = false
    @Published var status = ""
    @Published var error: String?
    @Published var columns: Int
    @Published var rows: Int
    @Published var metalActive = false
    private(set) var process: LocalProcess!
    private let bridge = ProcessBridge()
    private var logger: SessionLog?
    private var sshConnection: SSHConnection?
    private var socketDirectory: URL?
    private var started = false
    private var closed = false
    private var pasting = false

    init(target: LaunchTarget, configuration: Configuration, directory: String? = nil) {
        self.target = target
        title = target.name
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        columns = configuration.columns; rows = configuration.rows
        let options = TerminalOptions(cols: configuration.columns, rows: configuration.rows, cursorStyle: .blinkBar, scrollback: configuration.scrollback)
        terminal = NativeTerminalView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600), options: options)
        super.init()
        terminal.terminalDelegate = self
        terminal.session = self
        bridge.session = self
        bridge.updateSize(cols: columns, rows: rows, pixels: terminal.bounds.size)
        process = LocalProcess(delegate: bridge, dispatchQueue: .main)
        apply(configuration)
    }

    func apply(_ configuration: Configuration) {
        terminal.font = NSFont(name: configuration.fontFamily, size: configuration.fontSize) ?? .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        terminal.nativeForegroundColor = NSColor(hex: configuration.foreground)
        terminal.nativeBackgroundColor = NSColor(hex: configuration.background)
        terminal.backgroundOpacity = configuration.opacity
        terminal.caretColor = NSColor(hex: configuration.foreground)
        terminal.selectedTextBackgroundColor = .init(srgbRed: 0.32, green: 0.38, blue: 0.49, alpha: 0.65)
        terminal.optionAsMetaKey = configuration.optionAsMeta
        terminal.changeScrollback(configuration.scrollback)
        terminal.minimumContrastRatio = 1.2
        if terminal.window != nil {
            do { try terminal.setUseMetal(configuration.useMetal); metalActive = configuration.useMetal }
            catch { metalActive = false; Diagnostics.log("Metal unavailable: \(error)") }
        }
    }

    func start(configuration: Configuration) {
        guard !started else { apply(configuration); return }
        started = true
        apply(configuration)
        let executable: String, arguments: [String]
        do {
            switch target {
            case .shell(let path): executable = path; arguments = ["-l"]
            case .command(_, let command):
                guard !command.contains("\0") else { throw TerminalError.message("コマンドに NUL 文字は使用できません。") }
                executable = configuration.shell; arguments = ["-lc", command]
            case .ssh(let profile):
                try profile.validate()
                // OpenSSH's Unix-domain socket path must remain below 104 bytes on macOS.
                let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t2-" + String(id.uuidString.prefix(8)))
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                socketDirectory = folder
                let connection = SSHConnection(profile: profile, socket: folder.appendingPathComponent("s").path)
                sshConnection = connection
                executable = "/usr/bin/ssh"; arguments = connection.interactiveArguments
            }
            var environment = ProcessInfo.processInfo.environment
            environment["TERM"] = "xterm-256color"
            environment["COLORTERM"] = "truecolor"
            environment["TERM_PROGRAM"] = "Terminal2"
            environment["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
            if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
            let result = process.startProcessChecked(executable: executable, args: arguments, environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: directory)
            switch result {
            case .success: running = true; status = ""
            case .failure(let error): failed(String(describing: error))
            }
            Diagnostics.log("Session \(id) started target=\(target.name) pid=\(process.shellPid)")
        } catch { failed(error.localizedDescription) }
    }

    func receive(_ bytes: Data) {
        guard !closed else { return }
        let start = CFAbsoluteTimeGetCurrent()
        if let logger {
            do { try logger.append(bytes) }
            catch { self.logger = nil; recording = false; self.error = error.localizedDescription }
        }
        terminal.feed(byteArray: Array(bytes)[...])
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let threshold = Double(ProcessInfo.processInfo.environment["TERMINAL_SLOW_FRAME_MS"] ?? "16") ?? 16
        if elapsed > threshold { Diagnostics.log("parse=\(elapsed)ms bytes=\(bytes.count)", file: "perf.log") }
    }

    func didExit(_ code: Int32?) {
        running = false
        status = code.map { "終了コード \($0)" } ?? "終了しました"
        terminal.programStatusProcessExited()
        logger = nil; recording = false
        Diagnostics.log("Session \(id) exited status=\(code.map(String.init) ?? "signal")")
        cleanupSocket()
    }
    func failed(_ message: String) {
        running = false; error = message; status = "起動できませんでした"
        terminal.feed(text: "\r\n\(message)\r\n")
        Diagnostics.log("Session \(id) failed: \(message)")
        cleanupSocket()
    }
    func close() {
        guard !closed else { return }
        closed = true
        process.terminate()
        logger = nil; recording = false
        cleanupSocket()
    }
    private func cleanupSocket() {
        if let folder = socketDirectory { try? FileManager.default.removeItem(at: folder); socketDirectory = nil }
    }
    func toggleLog() {
        if recording { logger = nil; recording = false; return }
        do { logger = try SessionLog(id: id); recording = true }
        catch { self.error = error.localizedDescription }
    }

    func pasteClipboard() {
        guard running, !pasting else { return }
        let board = NSPasteboard.general
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            pasteFiles(files); return
        }
        if board.string(forType: .string) == nil, let image = NSImage(pasteboard: board),
           let tiff = image.tiffRepresentation, let representation = NSBitmapImageRep(data: tiff),
           let png = representation.representation(using: .png, properties: [:]) {
            do {
                let folder = AppPaths.support.appendingPathComponent("Pasted Images")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let path = folder.appendingPathComponent("paste-\(UUID().uuidString).png")
                try png.write(to: path, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                pasteFiles([path], removeAfterUpload: true)
            } catch { self.error = error.localizedDescription }
            return
        }
        if let text = board.string(forType: .string) { terminal.pasteText(text) }
    }

    func pasteFiles(_ files: [URL], removeAfterUpload: Bool = false) {
        guard !pasting, running else { return }
        guard let connection = sshConnection else {
            terminal.pasteText(files.map { Shell.quote($0.path) }.joined(separator: " "))
            return
        }
        pasting = true; status = "アップロード中…"
        Task { [weak self] in
            do {
                let paths = try await connection.upload(files)
                guard let self else { return }
                if !self.closed, self.running { self.terminal.pasteText(paths.map(Shell.quote).joined(separator: " ")) }
                if removeAfterUpload { for file in files { try? FileManager.default.removeItem(at: file) } }
                self.status = ""; self.pasting = false
            } catch {
                self?.pasting = false; self?.status = ""; self?.error = error.localizedDescription
            }
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        columns = newCols; rows = newRows
        bridge.updateSize(cols: newCols, rows: newRows, pixels: terminal.convertToBacking(terminal.bounds).size)
        var size = bridge.getWindowSize()
        _ = process?.updateWindowSize(&size)
    }
    func setTerminalTitle(source: TerminalView, title: String) { self.title = title.isEmpty ? target.name : String(title.prefix(512)) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let directory, let url = URL(string: directory), url.isFileURL { self.directory = url.path }
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { guard !closed else { return }; process.send(data: data) }
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        guard content.count <= 4 * 1024 * 1024, let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class NativeTerminalView: TerminalView {
    weak var session: TerminalSession?
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "ターミナル" }
    override func accessibilityValue() -> Any? {
        let rows = terminalInputStateSnapshot()?.dimensions.rows ?? 24
        return visibleRowsText(0..<rows).joined(separator: "\n")
    }
    override func accessibilitySelectedText() -> String? { getSelection() }
    override func paste(_ sender: Any) { session?.pasteClipboard() }
    override func rightMouseDown(with event: NSEvent) { session?.pasteClipboard() }
    override func rightMouseUp(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let previous = allowMouseReporting
        allowMouseReporting = false
        super.mouseDown(with: event)
        allowMouseReporting = previous
    }
    override func mouseDragged(with event: NSEvent) {
        let previous = allowMouseReporting; allowMouseReporting = false
        super.mouseDragged(with: event); allowMouseReporting = previous
    }
    override func mouseUp(with event: NSEvent) {
        let previous = allowMouseReporting; allowMouseReporting = false
        super.mouseUp(with: event); allowMouseReporting = previous
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        session?.pasteFiles(files); return true
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xE2E4E9
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var hex: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
