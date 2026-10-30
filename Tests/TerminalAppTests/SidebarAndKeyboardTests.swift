import XCTest
import AppKit
import TerminalCore
@testable import TerminalApp

final class SidebarAndKeyboardTests: XCTestCase {
    @MainActor
    func testShortcutRecorderAcceptsEscapeAndCommandKeys() {
        _ = NSApplication.shared
        let button = ShortcutRecorderButton()
        var recorded: [KeyChord] = []
        button.onChange = { recorded.append($0) }
        for (code, modifiers) in [(UInt16(53), NSEvent.ModifierFlags()), (UInt16(12), .command)] {
            button.beginRecording()
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            button.capture(event)
            XCTAssertFalse(button.recording)
        }
        XCTAssertEqual(recorded, [KeyChord(key: "escape"), KeyChord(key: "q", modifiers: ["command"])])
    }
    @MainActor
    func testActualWindowSeparatesTitlebarTerminalAndConnectionPanel() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(configurationURL: folder.appendingPathComponent("config.json"))
        defer { workspace.shutdown() }
        let controller = TerminalWindowController(workspace: workspace)
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertNil(controller.connectionPanel)
        workspace.sidebarVisible = true
        let panel = try XCTUnwrap(controller.connectionPanel)
        XCTAssertTrue(panel.parent === window)
        XCTAssertFalse(window.frame.intersects(panel.frame), "terminal=\(window.frame), panel=\(panel.frame)")
        workspace.sidebarVisible = false
        XCTAssertFalse(panel.isVisible)
        window.delegate = nil; window.close()
    }
    func testSidecarNeverOverlapsTerminalAndPreservesSizeWhenItFits() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        for x in [0.0, 300, 1000] {
            let terminal = CGRect(x: x, y: 100, width: 900, height: 700)
            let result = SidebarGeometry.layout(terminal: terminal, visible: screen)
            XCTAssertEqual(result.terminal.size, terminal.size)
            XCTAssertFalse(result.terminal.intersects(result.sidebar))
            XCTAssertTrue(screen.contains(result.sidebar))
            XCTAssertEqual(result.sidebar.maxY, result.terminal.maxY)
        }
    }

    func testSidecarFitsAlongsideAFullWidthWindowWithoutOverlap() {
        let screen = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        let result = SidebarGeometry.layout(terminal: screen, visible: screen)
        XCTAssertFalse(result.terminal.intersects(result.sidebar))
        XCTAssertTrue(screen.contains(result.terminal))
        XCTAssertTrue(screen.contains(result.sidebar))
    }

    @MainActor
    func testCommandArrowsAndRemappingUseActualKeyCodes() {
        var config = Configuration()
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .function, .numericPad], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f703}", charactersIgnoringModifiers: "\u{f703}", isARepeat: false, keyCode: 124)!
        XCTAssertEqual(ShortcutRouter.action(for: right, configuration: config, context: .terminal), .nextTab)
        config.assign(.unbound, to: .nextTab)
        XCTAssertNil(ShortcutRouter.action(for: right, configuration: config, context: .terminal))
        let f11 = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f70e}", charactersIgnoringModifiers: "\u{f70e}", isARepeat: false, keyCode: 103)!
        XCTAssertNil(ShortcutRouter.action(for: f11, configuration: config, context: .terminal))
    }

    @MainActor
    func testOptionArrowsReachRealPTYAsXtermMetaArrows() async throws {
        var config = Configuration(); config.useMetal = false
        let python = "import os,tty; tty.setraw(0); os.write(1,b'__READY__'); data=b''\nwhile len(data)<12: data+=os.read(0,12-len(data))\nos.write(1,b'__BYTES__'+data.hex().encode())"
        let session = TerminalSession(target: .command("bytes", "exec /usr/bin/python3 -c " + Shell.quote(python)), configuration: config)
        defer { session.close() }
        session.start(configuration: config)
        let deadline = Date().addingTimeInterval(8)
        while !session.terminal.visibleRowsText(0..<session.rows).joined().contains("__READY__") && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        for code: UInt16 in [123, 124] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, characters: code == 123 ? "\u{f702}" : "\u{f703}", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            let action = try XCTUnwrap(ShortcutRouter.action(for: event, configuration: config, context: .terminal))
            XCTAssertTrue(session.performTerminalAction(action))
        }
        while session.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let output = String(decoding: session.terminal.getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(output.contains("__BYTES__1b5b313b33441b5b313b3343"), output)
        XCTAssertFalse(session.running)
    }

    @MainActor
    func testRemappedInterruptStillSendsControlCToRealPTY() async throws {
        var config = Configuration(); config.useMetal = false
        config.assign(KeyChord(key: "x", modifiers: ["option"]), to: .copyOrInterrupt)
        let python = "import os,tty; tty.setraw(0); os.write(1,b'__READY__'); os.write(1,b'__CTRL__'+os.read(0,1).hex().encode())"
        let session = TerminalSession(target: .command("interrupt", "exec /usr/bin/python3 -c " + Shell.quote(python)), configuration: config)
        defer { session.close() }
        session.start(configuration: config)
        let deadline = Date().addingTimeInterval(5)
        while !session.terminal.visibleRowsText(0..<session.rows).joined().contains("__READY__") && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 7)!
        let action = try XCTUnwrap(ShortcutRouter.action(for: event, configuration: config, context: .terminal))
        XCTAssertTrue(session.performTerminalAction(action))
        while session.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(String(decoding: session.terminal.getBufferAsData(), as: UTF8.self).contains("__CTRL__03"))
        XCTAssertFalse(session.running)
    }

    @MainActor
    func testOptionArrowsSwitchRealTmuxSessions() async throws {
        guard let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw XCTSkip("tmux is not installed") }
        let socket = "/tmp/t2-tmux-" + String(UUID().uuidString.prefix(8))
        func command(_ args: [String]) async throws -> CommandOutput { try await CommandRunner.run(tmux, ["-S", socket, "-f", "/dev/null"] + args) }
        let started = try await command(["new-session", "-d", "-s", "one"])
        XCTAssertEqual(started.status, 0, started.text)
        defer {
            let cleanup = Process(); cleanup.executableURL = URL(fileURLWithPath: tmux); cleanup.arguments = ["-S", socket, "kill-server"]
            cleanup.standardOutput = FileHandle.nullDevice; cleanup.standardError = FileHandle.nullDevice
            do { try cleanup.run(); cleanup.waitUntilExit() } catch {}
        }
        _ = try await command(["new-session", "-d", "-s", "two"])
        _ = try await command(["bind-key", "-T", "root", "M-Right", "switch-client", "-n"])
        _ = try await command(["bind-key", "-T", "root", "M-Left", "switch-client", "-p"])
        _ = try await command(["set-option", "-s", "escape-time", "0"])
        var config = Configuration(); config.useMetal = false
        let session = TerminalSession(target: .command("tmux", "exec " + Shell.quote(tmux) + " -S " + Shell.quote(socket) + " attach-session -t one"), configuration: config)
        defer { session.close() }
        session.start(configuration: config)
        func waitForSession(_ name: String) async throws {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if try await command(["list-clients", "-F", "#{session_name}"]).text.trimmingCharacters(in: .whitespacesAndNewlines) == name { return }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTFail("tmux did not switch to \(name)")
        }
        try await waitForSession("one")
        for (code, target) in [(UInt16(124), "two"), (UInt16(123), "one")] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            let action = try XCTUnwrap(ShortcutRouter.action(for: event, configuration: config, context: .terminal))
            XCTAssertTrue(session.performTerminalAction(action))
            try await waitForSession(target)
        }
    }
}
