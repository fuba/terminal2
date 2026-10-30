import AppKit
import SwiftUI
import Carbon
import TerminalCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let workspace = Workspace(configurationURL: ProcessInfo.processInfo.environment["TERMINAL2_CONFIG"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? AppPaths.config)
    private var terminalWindow: TerminalWindowController!
    private var settingsWindow: NSWindow?
    private let hotkey = GlobalHotkey()
    private var lastHotkey: HotkeyConfiguration?
    private var keyMonitor: Any?
    private var profilingTimer: Timer?
    private var shortcutItems: [ShortcutAction: NSMenuItem] = [:]
    private var recordingShortcut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        terminalWindow = TerminalWindowController(workspace: workspace)
        workspace.onConfigurationChanged = { [weak self] in self?.configurationChanged() }
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
            if let recorder = NSApp.keyWindow?.firstResponder as? ShortcutRecorderButton, recorder.recording {
                recorder.capture(event); return nil
            }
            guard let self else { return event }
            if self.hotkey.matches(event) { self.toggleWindow(); return nil }
            let context = self.shortcutContext
            if let action = ShortcutRouter.action(for: event, configuration: self.workspace.configuration, context: context), self.perform(action) { return nil }
            // SwiftTerm has an internal Option-Command-O binding; the host owns all app shortcuts.
            if context == .terminal, ShortcutRouter.chord(for: event) == KeyChord(key: "o", modifiers: ["option", "command"]) { return nil }
            return event
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
        guard !recordingShortcut, lastHotkey != workspace.configuration.hotkey else { return }
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
    private var shortcutContext: ShortcutContext {
        if NSApp.keyWindow?.attachedSheet != nil || NSApp.modalWindow != nil { return .modal }
        if NSApp.keyWindow === settingsWindow || NSApp.keyWindow === NSFontManager.shared.fontPanel(false) { return .settings }
        if let terminal = workspace.selected?.terminal, NSApp.keyWindow?.firstResponder === terminal { return .terminal }
        if NSApp.keyWindow === terminalWindow?.connectionPanel { return .connections }
        if workspace.showingSearch && NSApp.keyWindow === terminalWindow?.window { return .search }
        return NSApp.keyWindow === terminalWindow?.window ? .connections : .settings
    }

    private func configurationChanged() {
        updateHotkey()
        for (action, item) in shortcutItems {
            let chord = workspace.configuration.binding(for: action)
            item.keyEquivalent = ShortcutRouter.menuEquivalent(chord)
            item.keyEquivalentModifierMask = ShortcutRouter.modifiers(chord)
        }
        settingsWindow?.appearance = terminalWindow?.window?.appearance
    }

    func setRecordingShortcut(_ recording: Bool) {
        recordingShortcut = recording
        if recording {
            var disabled = workspace.configuration.hotkey; disabled.enabled = false
            try? hotkey.register(disabled)
        } else { lastHotkey = nil; updateHotkey() }
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ShortcutAction(rawValue: raw) else { return }
        _ = perform(action)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let raw = menuItem.representedObject as? String, let action = ShortcutAction(rawValue: raw) else { return true }
        return action.allows(shortcutContext)
    }

    @discardableResult
    func perform(_ action: ShortcutAction) -> Bool {
        if let index = action.tabIndex {
            if workspace.sessions.indices.contains(index) { workspace.select(workspace.sessions[index].id) }
            return true
        }
        if workspace.selected?.performTerminalAction(action) == true { return true }
        switch action {
        case .newTab: terminalWindow.showWindow(nil); workspace.open()
        case .closeTab:
            if let key = NSApp.keyWindow, key !== terminalWindow.window, key !== terminalWindow.connectionPanel { key.close() }
            else if let session = workspace.selected { workspace.close(session) }
        case .nextTab: workspace.cycle(1)
        case .previousTab: workspace.cycle(-1)
        case .newSSH: terminalWindow.showWindow(nil); workspace.showingConnect = true
        case .connectionPicker: terminalWindow.showWindow(nil); workspace.showingPicker = true
        case .toggleSidebar: workspace.sidebarVisible.toggle()
        case .find: workspace.showingSearch = true
        case .searchNext: workspace.searchHandler?(false)
        case .searchPrevious: workspace.searchHandler?(true)
        case .closeSearch:
            workspace.selected?.terminal.clearSearch(); workspace.showingSearch = false; workspace.focusSelected()
        case .copy: return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case .paste: return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case .selectAll: return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case .toggleLog: workspace.selected?.toggleLog()
        case .showLogs: NSWorkspace.shared.open(AppPaths.logs)
        case .zoomIn: workspace.configuration.fontSize = min(128, workspace.configuration.fontSize + 1)
        case .zoomOut: workspace.configuration.fontSize = max(8, workspace.configuration.fontSize - 1)
        case .resetZoom: workspace.configuration.fontSize = 15
        case .showFonts: showFonts()
        case .fitHeight: terminalWindow.toggleHeight()
        case .fullScreen: terminalWindow.window?.toggleFullScreen(nil)
        case .settings: showSettings(nil)
        case .hideApp: NSApp.hide(nil)
        case .quitApp: NSApp.terminate(nil)
        default: return false
        }
        return true
    }

    func showFonts() {
        let manager = NSFontManager.shared
        manager.target = self; manager.action = #selector(changeFont(_:))
        let config = workspace.configuration
        manager.setSelectedFont(NSFont(name: config.fontFamily, size: config.fontSize) ?? .monospacedSystemFont(ofSize: config.fontSize, weight: .regular), isMultiple: false)
        manager.orderFrontFontPanel(self)
        manager.fontPanel(true)?.makeKeyAndOrderFront(self)
    }

    @objc func changeFont(_ sender: NSFontManager) {
        let config = workspace.configuration
        let font = NSFont(name: config.fontFamily, size: config.fontSize) ?? .monospacedSystemFont(ofSize: config.fontSize, weight: .regular)
        let selected = sender.convert(font)
        var next = config
        next.fontFamily = selected.fontName; next.fontSize = min(128, max(8, selected.pointSize))
        workspace.configuration = next
    }

    private func buildMenu() {
        let main = NSMenu(); NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func add(_ action: ShortcutAction, to menu: NSMenu) {
            let chord = workspace.configuration.binding(for: action)
            let item = NSMenuItem(title: action.title, action: #selector(runCommand(_:)), keyEquivalent: ShortcutRouter.menuEquivalent(chord))
            item.keyEquivalentModifierMask = ShortcutRouter.modifiers(chord)
            item.target = self; item.representedObject = action.rawValue
            menu.addItem(item); shortcutItems[action] = item
        }
        let app = menu("Terminal2")
        let about = NSMenuItem(title: "Terminal2 について", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp; app.addItem(about)
        add(.settings, to: app)
        app.addItem(.separator())
        let services = NSMenu(title: "サービス")
        let servicesItem = NSMenuItem(title: "サービス", action: nil, keyEquivalent: ""); servicesItem.submenu = services
        app.addItem(servicesItem); NSApp.servicesMenu = services
        app.addItem(.separator()); add(.hideApp, to: app); add(.quitApp, to: app)
        let file = menu("ファイル")
        for action in [ShortcutAction.newTab, .newSSH, .connectionPicker, .closeTab, .toggleLog, .showLogs] { add(action, to: file) }
        let edit = menu("編集")
        for action in [ShortcutAction.copy, .paste, .selectAll] { add(action, to: edit) }
        edit.addItem(.separator()); add(.find, to: edit)
        let view = menu("表示")
        for action in [ShortcutAction.toggleSidebar, .showFonts, .zoomIn, .zoomOut, .resetZoom, .fitHeight, .fullScreen] { add(action, to: view) }
        view.addItem(.separator())
        for action in [ShortcutAction.historyUp, .historyDown, .historyTop, .historyBottom, .clearHistory] { add(action, to: view) }
        let window = menu("ウィンドウ"); NSApp.windowsMenu = window
        add(.nextTab, to: window); add(.previousTab, to: window); window.addItem(.separator())
        for action in ShortcutAction.allCases where action.tabIndex != nil { add(action, to: window) }
    }
}
