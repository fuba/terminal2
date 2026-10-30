import AppKit
import SwiftUI
import TerminalCore

@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let workspace: Workspace
    private var docked = false
    private var undockedFrame: NSRect?
    private var adjustingFrame = false
    private var screensObserver: NSObjectProtocol?
    private let toolbarID = NSToolbar.Identifier("TerminalToolbar")
    private(set) var connectionPanel: NSPanel?
    private var panelHostingView: NSView?
    private var frameBeforeSidebar: NSRect?
    private var fittedSidebarFrame: NSRect?

    init(workspace: Workspace) {
        self.workspace = workspace
        let config = workspace.configuration
        let width = max(800, Double(config.columns) * config.fontSize * 0.61 + 24)
        let height = max(480, Double(config.rows) * config.fontSize * 1.25 + 100)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        workspace.windowController = self
        window.delegate = self
        window.title = "Terminal2"
        window.subtitle = "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev")
        window.minSize = NSSize(width: 720, height: 420)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: toolbarID)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        let hosting = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        restorePosition()
        applyAppearance()
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyAppearance() {
        guard let window else { return }
        window.isOpaque = workspace.configuration.opacity == 1
        window.backgroundColor = window.isOpaque ? NSColor(hex: workspace.configuration.background) : .clear
        window.appearance = NSAppearance(named: NSColor(hex: workspace.configuration.background).isLight ? .aqua : .darkAqua)
        connectionPanel?.appearance = window.appearance
    }
    func resizeToGrid() {
        guard let window, let session = workspace.selected else { return }
        session.terminal.resize(cols: workspace.configuration.columns, rows: workspace.configuration.rows)
        let optimal = session.terminal.getOptimalFrameSize()
        let delta = NSSize(width: optimal.width - session.terminal.bounds.width, height: optimal.height - session.terminal.bounds.height)
        var frame = window.frame
        frame.origin.y -= delta.height
        frame.size.width += delta.width; frame.size.height += delta.height
        window.setFrame(fit(frame), display: true)
    }
    func toggleHeight() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if docked {
            docked = false
            if let frame = undockedFrame { window.setFrame(fit(frame), display: true, animate: false) }
        } else {
            undockedFrame = window.frame; docked = true
            snapHeight()
        }
    }
    private func snapHeight() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        var frame = window.frame
        frame.origin.y = screen.visibleFrame.origin.y; frame.size.height = screen.visibleFrame.height
        window.setFrame(frame, display: true, animate: false)
    }
    private func displayID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }
    private func savePosition() {
        guard !adjustingFrame, !docked, let window, !window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
        var positions = UserDefaults.standard.dictionary(forKey: "displayFrames") as? [String: String] ?? [:]
        positions[displayID(screen)] = NSStringFromRect(window.frame)
        UserDefaults.standard.set(positions, forKey: "displayFrames")
        UserDefaults.standard.set(displayID(screen), forKey: "lastDisplay")
    }
    private func restorePosition() {
        guard let window else { return }
        let positions = UserDefaults.standard.dictionary(forKey: "displayFrames") as? [String: String] ?? [:]
        let last = UserDefaults.standard.string(forKey: "lastDisplay")
        let screen = NSScreen.screens.first { displayID($0) == last } ?? NSScreen.main
        if let screen, let string = positions[displayID(screen)] {
            window.setFrame(fit(NSRectFromString(string), on: screen), display: true)
        } else { window.setFrame(fit(window.frame), display: true) }
    }
    private func fit(_ frame: NSRect, on screen: NSScreen? = nil) -> NSRect {
        guard let screen = screen ?? window?.screen ?? NSScreen.main else { return frame }
        let visible = screen.visibleFrame
        let width = min(max(frame.width, 720), visible.width)
        let height = min(max(frame.height, 420), visible.height)
        return NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - width), y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width, height: height)
    }
    private func screensChanged() {
        guard let window else { return }
        adjustingFrame = true
        if docked { snapHeight() } else { window.setFrame(fit(window.frame), display: true) }
        adjustingFrame = false
        positionSidebar()
    }
    func windowDidMove(_ notification: Notification) { positionSidebar(); savePosition() }
    func windowDidResize(_ notification: Notification) { positionSidebar(); savePosition() }
    func windowDidChangeScreen(_ notification: Notification) { if docked { snapHeight() }; positionSidebar(); savePosition() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func windowWillEnterFullScreen(_ notification: Notification) {
        if workspace.sidebarVisible { workspace.sidebarVisible = false }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        if workspace.sidebarVisible { setSidebarVisible(true) }
    }

    func setSidebarVisible(_ visible: Bool) {
        guard let window else { return }
        if !visible {
            connectionPanel?.orderOut(nil)
            if let before = frameBeforeSidebar, let fitted = fittedSidebarFrame, window.frame == fitted {
                adjustingFrame = true; window.setFrame(before, display: true); adjustingFrame = false
            }
            frameBeforeSidebar = nil; fittedSidebarFrame = nil
            window.makeKeyAndOrderFront(nil); workspace.focusSelected()
            return
        }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return }
        if connectionPanel == nil {
            let panel = ConnectionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "接続"
            panel.isReleasedWhenClosed = false; panel.isFloatingPanel = false; panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.collectionBehavior = [.fullScreenAuxiliary]
            let effect = NSVisualEffectView()
            effect.material = .sidebar; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = 12; effect.layer?.masksToBounds = true
            let hosting = NSHostingView(rootView: ConnectionSidebar(workspace: workspace))
            hosting.sizingOptions = []; hosting.frame = effect.bounds; hosting.autoresizingMask = [.width, .height]
            effect.addSubview(hosting); panel.contentView = effect
            panelHostingView = hosting
            panel.appearance = window.appearance
            connectionPanel = panel
            window.addChildWindow(panel, ordered: .below)
        }
        frameBeforeSidebar = window.frame
        positionSidebar()
        guard let panel = connectionPanel else { return }
        let frame = panel.frame
        let offset: CGFloat = frame.midX < window.frame.midX ? 18 : -18
        // Keep window geometry final even when the window server pauses animations.
        // Animate only clipped contents so the panel can never cross the terminal surface.
        panelHostingView?.setFrameOrigin(NSPoint(x: offset, y: 0))
        panel.alphaValue = 0; panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 1
            panelHostingView?.animator().setFrameOrigin(.zero)
        }
        workspace.focusSelected()
    }

    private func positionSidebar() {
        guard !adjustingFrame, workspace.sidebarVisible, let window, let panel = connectionPanel,
              let screen = window.screen ?? NSScreen.main else { return }
        adjustingFrame = true
        defer { adjustingFrame = false }
        let layout = SidebarGeometry.layout(terminal: window.frame, visible: screen.visibleFrame)
        if layout.terminal != window.frame {
            if frameBeforeSidebar == nil { frameBeforeSidebar = window.frame }
            window.setFrame(layout.terminal, display: true)
            fittedSidebarFrame = layout.terminal
        }
        panel.setFrame(layout.sidebar, display: true)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("sidebar"), .flexibleSpace, .init("connect"), .init("search"), .init("newTab"), .init("settings")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let name: String, image: String, action: Selector
        switch id.rawValue {
        case "sidebar": name = "サイドバー"; image = "sidebar.left"; action = #selector(toggleSidebar)
        case "connect": name = "SSH 接続"; image = "network"; action = #selector(connect)
        case "search": name = "検索"; image = "magnifyingglass"; action = #selector(find)
        case "newTab": name = "新しいタブ"; image = "plus"; action = #selector(newTab)
        case "settings": name = "設定"; image = "slider.horizontal.3"; action = #selector(settings)
        default: return nil
        }
        item.label = name; item.toolTip = name; item.image = NSImage(systemSymbolName: image, accessibilityDescription: name)
        item.target = self; item.action = action
        return item
    }
    @objc private func toggleSidebar() { workspace.sidebarVisible.toggle() }
    @objc private func connect() { workspace.showingConnect = true }
    @objc private func find() { workspace.showingSearch.toggle() }
    @objc private func newTab() { workspace.open() }
    @objc private func settings() { (NSApp.delegate as? AppDelegate)?.showSettings(nil) }
}

private final class ConnectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
