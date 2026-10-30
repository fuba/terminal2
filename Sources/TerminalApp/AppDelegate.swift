import AppKit
import SwiftUI
import Carbon
import TerminalCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspace = Workspace()
    private var terminalWindow: TerminalWindowController!
    private var settingsWindow: NSWindow?
    private let hotkey = GlobalHotkey()
    private var lastHotkey: HotkeyConfiguration?
    private var keyMonitor: Any?
    private var profilingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        terminalWindow = TerminalWindowController(workspace: workspace)
        workspace.onConfigurationChanged = { [weak self] in self?.updateHotkey() }
        hotkey.onPress = { [weak self] in self?.toggleWindow() }
        updateHotkey()
        profilingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in Diagnostics.recordPerformance() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            if event.type == .scrollWheel, event.modifierFlags.contains(.shift),
               let terminal = self?.workspace.selected?.terminal, event.window === terminal.window,
               terminal.bounds.contains(terminal.convert(event.locationInWindow, from: nil)) {
                let lines = min(64, max(1, Int(abs(event.scrollingDeltaY) / (event.hasPreciseScrollingDeltas ? 10 : 1))))
                if event.scrollingDeltaY > 0 { terminal.scrollUp(lines: lines) }
                else if event.scrollingDeltaY < 0 { terminal.scrollDown(lines: lines) }
                return nil
            }
            guard event.type == .keyDown else { return event }
            if self?.hotkey.matches(event) == true { self?.toggleWindow(); return nil }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
                  event.charactersIgnoringModifiers == "c", let terminal = self?.workspace.selected?.terminal,
                  NSApp.keyWindow?.firstResponder === terminal, terminal.selectionActive else { return event }
            terminal.copy(terminal)
            return nil
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if workspace.sessions.isEmpty {
            let path = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
            workspace.open(directory: path)
        }
        terminalWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        terminalWindow?.showWindow(nil); workspace.focusSelected(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        profilingTimer?.invalidate()
        Diagnostics.recordPerformance()
        workspace.shutdown()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory) {
                workspace.open(directory: directory.boolValue ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path)
            }
        }
        terminalWindow?.showWindow(nil)
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func openFolder(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty, let files = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            application(NSApp, openFiles: files)
        } else { application(NSApp, openFiles: urls.map(\.path)) }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func updateHotkey() {
        guard lastHotkey != workspace.configuration.hotkey else { return }
        lastHotkey = workspace.configuration.hotkey
        do { try hotkey.register(workspace.configuration.hotkey) }
        catch { workspace.error = error.localizedDescription; Diagnostics.log("Hotkey: \(error)") }
    }
    private func toggleWindow() {
        guard let window = terminalWindow.window else { return }
        if NSApp.isActive && window.isVisible {
            Diagnostics.log("Hotkey hide")
            window.orderOut(nil); NSApp.hide(nil)
        } else {
            Diagnostics.log("Hotkey show")
            terminalWindow.showWindow(nil); NSApp.activate(ignoringOtherApps: true); workspace.focusSelected()
        }
    }
    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Terminal2 設定"
            window.contentView = NSHostingView(rootView: SettingsView(workspace: workspace))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func newTab(_ sender: Any?) { terminalWindow.showWindow(nil); workspace.open() }
    @objc private func closeTab(_ sender: Any?) {
        if NSApp.keyWindow === settingsWindow { settingsWindow?.close(); return }
        if let session = workspace.selected { workspace.close(session) }
    }
    @objc private func nextTab(_ sender: Any?) { workspace.cycle(1) }
    @objc private func previousTab(_ sender: Any?) { workspace.cycle(-1) }
    @objc private func selectTab(_ sender: NSMenuItem) { if workspace.sessions.indices.contains(sender.tag) { workspace.select(workspace.sessions[sender.tag].id) } }
    @objc private func connect(_ sender: Any?) { workspace.showingConnect = true; terminalWindow.showWindow(nil) }
    @objc private func picker(_ sender: Any?) { workspace.showingPicker = true; terminalWindow.showWindow(nil) }
    @objc private func toggleLog(_ sender: Any?) { workspace.selected?.toggleLog() }
    @objc private func find(_ sender: Any?) { workspace.showingSearch = true }
    @objc private func toggleSidebar(_ sender: Any?) { workspace.sidebarVisible.toggle() }
    @objc private func dockHeight(_ sender: Any?) { terminalWindow.toggleHeight() }
    @objc private func zoomIn(_ sender: Any?) { workspace.configuration.fontSize = min(48, workspace.configuration.fontSize + 1) }
    @objc private func zoomOut(_ sender: Any?) { workspace.configuration.fontSize = max(8, workspace.configuration.fontSize - 1) }
    @objc private func resetZoom(_ sender: Any?) { workspace.configuration.fontSize = 15 }
    @objc private func historyUp(_ sender: Any?) { workspace.selected?.terminal.pageUp() }
    @objc private func historyDown(_ sender: Any?) { workspace.selected?.terminal.pageDown() }
    @objc private func historyTop(_ sender: Any?) { workspace.selected?.terminal.scroll(toPosition: 0) }
    @objc private func historyBottom(_ sender: Any?) { workspace.selected?.terminal.scroll(toPosition: 1) }
    @objc private func showLogs(_ sender: Any?) { NSWorkspace.shared.open(AppPaths.logs) }
    @objc private func clearHistory(_ sender: Any?) { workspace.selected?.terminal.clearScrollback() }
    @objc private func fullScreen(_ sender: Any?) { terminalWindow.window?.toggleFullScreen(sender) }

    private func buildMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        @discardableResult
        func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target ?? self
            menu.addItem(item); return item
        }
        let app = menu("Terminal2")
        item(app, "Terminal2 について", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        item(app, "設定…", #selector(showSettings(_:)), ",")
        app.addItem(.separator())
        let services = NSMenu(title: "サービス")
        let serviceItem = item(app, "サービス", nil); serviceItem.submenu = services; NSApp.servicesMenu = services
        app.addItem(.separator())
        item(app, "Terminal2 を隠す", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app, "Terminal2 を終了", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = menu("ファイル")
        item(file, "新しいタブ", #selector(newTab(_:)), "t")
        item(file, "SSH 接続…", #selector(connect(_:)), "s", modifiers: [.command, .shift])
        item(file, "接続先を選ぶ…", #selector(picker(_:)), "k")
        file.addItem(.separator())
        item(file, "タブを閉じる", #selector(closeTab(_:)), "w")
        item(file, "セッションログを切り替える", #selector(toggleLog(_:)), "l")
        item(file, "ログを表示", #selector(showLogs(_:)))
        let edit = menu("編集")
        let copy = item(edit, "コピー", #selector(NSText.copy(_:)), "c"); copy.target = nil
        let paste = item(edit, "ペースト", #selector(NSText.paste(_:)), "v"); paste.target = nil
        let select = item(edit, "すべて選択", #selector(NSText.selectAll(_:)), "a"); select.target = nil
        edit.addItem(.separator())
        item(edit, "検索…", #selector(find(_:)), "f")
        let view = menu("表示")
        item(view, "サイドバーを切り替える", #selector(toggleSidebar(_:)), "l", modifiers: [.command, .shift])
        item(view, "拡大", #selector(zoomIn(_:)), "+")
        item(view, "縮小", #selector(zoomOut(_:)), "-")
        item(view, "実際のサイズ", #selector(resetZoom(_:)), "0")
        view.addItem(.separator())
        item(view, "画面の高さに合わせる", #selector(dockHeight(_:)), String(UnicodeScalar(NSF11FunctionKey)!), modifiers: [])
        item(view, "フルスクリーン", #selector(fullScreen(_:)), "f", modifiers: [.command, .control])
        view.addItem(.separator())
        item(view, "履歴を上へ", #selector(historyUp(_:)), String(UnicodeScalar(NSPageUpFunctionKey)!), modifiers: [.shift])
        item(view, "履歴を下へ", #selector(historyDown(_:)), String(UnicodeScalar(NSPageDownFunctionKey)!), modifiers: [.shift])
        item(view, "履歴の先頭", #selector(historyTop(_:)), String(UnicodeScalar(NSHomeFunctionKey)!), modifiers: [.command])
        item(view, "履歴の末尾", #selector(historyBottom(_:)), String(UnicodeScalar(NSEndFunctionKey)!), modifiers: [.command])
        item(view, "履歴を消去", #selector(clearHistory(_:)), "k", modifiers: [.command, .shift])
        let window = menu("ウィンドウ")
        NSApp.windowsMenu = window
        item(window, "次のタブ", #selector(nextTab(_:)), "]", modifiers: [.command, .shift])
        item(window, "前のタブ", #selector(previousTab(_:)), "[", modifiers: [.command, .shift])
        window.addItem(.separator())
        for index in 0..<9 { item(window, "タブ \(index + 1)", #selector(selectTab(_:)), String(index + 1)).tag = index }
    }
}
