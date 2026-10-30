import XCTest
@testable import TerminalCore

final class CoreTests: XCTestCase {
    func testEscapeFilterAcrossEveryChunkBoundary() {
        let input = Array("hello\u{1b}[31m赤\u{1b}[0m\r\n\u{1b}]0;secret title\u{07}world\u{1b}Pqimage\u{1b}\\!\u{1b}]52;c;c2VjcmV0\u{1b}\\".utf8)
        for split in 0...input.count {
            var filter = EscapeFilter()
            let output = filter.consume(Data(input[..<split])) + filter.consume(Data(input[split...]))
            XCTAssertEqual(String(decoding: output, as: UTF8.self), "hello赤\nworld!", "split \(split)")
        }
    }

    func testShellQuotingCannotExecuteSubstitution() async throws {
        let dangerous = "a'b;$(touch /tmp/terminal2-should-not-exist)\n日本語"
        let output = try await CommandRunner.run("/bin/sh", ["-c", "printf %s " + Shell.quote(dangerous)])
        XCTAssertEqual(output.text, dangerous)
    }

    func testSSHArgumentsKeepDestinationAndCommandsSeparate() {
        let profile = SSHProfile(name: "Production", host: "example.com", user: "ec", port: 2222, identityFile: "~/.ssh/id_ed25519")
        let connection = SSHConnection(profile: profile, socket: "/tmp/t2/socket")
        let args = connection.interactiveArguments
        XCTAssertEqual(args.suffix(2), ["--", "ec@example.com"])
        XCTAssertTrue(args.contains("2222"))
        XCTAssertFalse(args.contains(where: { $0.contains("StrictHostKeyChecking=no") }))
        XCTAssertThrowsError(try SSHProfile(name: "Bad", host: "-oProxyCommand=bad").validate())
        XCTAssertThrowsError(try SSHProfile(name: "Bad", host: "host", user: "bad\nname").validate())
    }

    func testSSHConfigIncludesAndQuotedAliases() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "Host inner\n HostName example.org\n".write(to: dir.appendingPathComponent("extra"), atomically: true, encoding: .utf8)
        try "Include extra\nHost first second *.wild !excluded\n User ec\nHost \"with-dash\" # comment\n".write(to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SSHConfigDiscovery.aliases(at: dir.appendingPathComponent("config")), ["first", "inner", "second", "with-dash"])
    }

    func testConfigurationDefaultsAndValidation() throws {
        let config = try JSONDecoder().decode(Configuration.self, from: Data("{\"fontSize\":19}".utf8))
        XCTAssertEqual(config.fontSize, 19)
        XCTAssertEqual(config.scrollback, 10000)
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: Data("{\"fontSize\":-1}".utf8)).validated())
        let roundTrip = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(roundTrip, config)
    }

    func testTailscaleJSONAndDeterministicSorting() throws {
        let data = Data(#"{"Peer":{"2":{"HostName":"beta","DNSName":"beta.tail.example.","TailscaleIPs":["100.1.2.3"],"Online":false},"1":{"HostName":"alpha","DNSName":"alpha.tail.example.","TailscaleIPs":["100.1.2.4"],"Online":true}}}"#.utf8)
        let peers = try TailscalePeer.decode(data)
        XCTAssertEqual(peers.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(peers.first?.host, "alpha.tail.example")
        XCTAssertEqual(peers.first?.online, true)
    }

    func testRunnerDrainsLargeOutputAndTimesOut() async throws {
        let output = try await CommandRunner.run("/usr/bin/head", ["-c", "200000", "/dev/zero"])
        XCTAssertEqual(output.data.count, 200000)
        do {
            _ = try await CommandRunner.run("/bin/sh", ["-c", "sleep 10 & wait"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("タイムアウト")) }
        do {
            _ = try await CommandRunner.run("/usr/bin/head", ["-c", "100000", "/dev/zero"], outputLimit: 1024)
            XCTFail("Expected output limit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("上限")) }
    }
}
