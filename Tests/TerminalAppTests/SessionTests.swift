import XCTest
import AppKit
import SwiftTerm
import TerminalCore
@testable import TerminalApp

final class SessionTests: XCTestCase {
    @MainActor
    func testRealPTYUTF8TitleExitAndWindowSize() async throws {
        var configuration = Configuration()
        configuration.useMetal = false
        let command = #"printf '\033]0;PTY integration\007'; printf '日本語 PTY OK\n'; stty size; exit 7"#
        let session = TerminalSession(target: .command("test", command), configuration: configuration)
        defer { session.close() }
        session.start(configuration: configuration)
        let expectedSize = "\(session.rows) \(session.columns)"
        XCTAssertTrue(session.running)
        let deadline = Date().addingTimeInterval(8)
        while session.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(session.running)
        XCTAssertEqual(session.title, "PTY integration")
        XCTAssertEqual(session.status, "終了コード 7")
        let output = String(decoding: session.terminal.getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(output.contains("日本語 PTY OK"), output)
        XCTAssertTrue(output.contains(expectedSize), output)
    }

    @MainActor
    func testVTModeChangesAlternateScreenAndSplitUTF8() async throws {
        let view = NativeTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400), options: TerminalOptions(cols: 40, rows: 12))
        view.feed(text: "normal\u{1b}[?1049h\u{1b}[?2004h\u{1b}[?1h\u{1b}[38;2;255;100;50m")
        let bytes = Array("日本語".utf8)
        for byte in bytes { view.feed(byteArray: [byte][...]) }
        let state = try XCTUnwrap(view.terminalInputStateSnapshot())
        XCTAssertTrue(state.isAlternateBuffer)
        XCTAssertTrue(state.bracketedPasteMode)
        XCTAssertTrue(state.applicationCursor)
        XCTAssertTrue(view.visibleRowsText(0..<12).joined().contains("日本語"))
        view.feed(text: "\u{1b}[?1049l")
        XCTAssertTrue(view.visibleRowsText(0..<12).joined().contains("normal"))
    }

    @MainActor
    func testResizePropagatesToActualPTY() async throws {
        var configuration = Configuration(); configuration.useMetal = false
        let session = TerminalSession(target: .shell("/bin/sh"), configuration: configuration)
        defer { session.close() }
        session.start(configuration: configuration)
        session.terminal.resize(cols: 93, rows: 27)
        session.sizeChanged(source: session.terminal, newCols: 93, newRows: 27)
        session.terminal.send(txt: "stty size; printf '__DONE__\\n'; exit\n")
        let deadline = Date().addingTimeInterval(8)
        while session.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let output = String(decoding: session.terminal.getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(output.contains("27 93"), output)
        XCTAssertFalse(session.running)
    }

    @MainActor
    func testLiveAppearanceAndOSC52Policy() async {
        var config = Configuration(); config.useMetal = false
        let session = TerminalSession(target: .shell("/bin/zsh"), configuration: config)
        config.fontSize = 21; config.opacity = 0.7
        session.apply(config)
        XCTAssertEqual(session.terminal.font.pointSize, 21)
        XCTAssertEqual(session.terminal.backgroundOpacity, 0.7, accuracy: 0.001)
        XCTAssertNil(session.clipboardRead(source: session.terminal))
        session.close()
    }

    @MainActor
    func testNativeIMECompositionAndCandidateRect() async {
        let view = NativeTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400), options: TerminalOptions(cols: 80, rows: 24))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        var actual = NSRange()
        let rect = view.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: &actual)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertGreaterThanOrEqual(rect.minX, window.frame.minX)
        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        window.close()
    }

    func testSessionLogStripsControlPayloadAndKeepsJapanese() throws {
        try AppPaths.prepare()
        var log: SessionLog? = try SessionLog(id: UUID())
        let url = try XCTUnwrap(log?.url)
        defer { try? FileManager.default.removeItem(at: url) }
        try log?.append(Data("\u{1b}[31m日本語\u{1b}[0m\n\u{1b}]52;c;c2Vj".utf8))
        try log?.append(Data("cmV0\u{07}OK".utf8))
        log = nil
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("日本語\nOK"))
        XCTAssertFalse(text.contains("c2Vj"))
        XCTAssertFalse(text.contains("\u{1b}"))
    }
}
