import XCTest
import Foundation
import Darwin
@testable import TerminalCore

final class SSHIntegrationTests: XCTestCase {
    func testOpenSSHAuthenticationMultiplexingAndFileUpload() async throws {
        let folder = URL(fileURLWithPath: "/tmp/t2-test-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["host", "client"] {
            let result = try await CommandRunner.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", folder.appendingPathComponent(name).path])
            XCTAssertEqual(result.status, 0, result.text)
        }
        let port = try unusedPort()
        let hostKey = try String(contentsOf: folder.appendingPathComponent("host.pub"), encoding: .utf8)
        try "[127.0.0.1]:\(port) \(hostKey)".write(to: folder.appendingPathComponent("known_hosts"), atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(at: folder.appendingPathComponent("client.pub"), to: folder.appendingPathComponent("authorized_keys"))
        let config = """
        Port \(port)
        ListenAddress 127.0.0.1
        HostKey \(folder.path)/host
        PidFile \(folder.path)/pid
        AuthorizedKeysFile \(folder.path)/authorized_keys
        StrictModes no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        AllowUsers \(NSUserName())
        Subsystem sftp internal-sftp
        LogLevel VERBOSE
        """
        try config.write(to: folder.appendingPathComponent("sshd_config"), atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        server.arguments = ["-D", "-e", "-f", folder.appendingPathComponent("sshd_config").path]
        let log = folder.appendingPathComponent("sshd.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }
        server.standardOutput = logHandle; server.standardError = logHandle
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }

        let profile = SSHProfile(name: "loopback", host: "127.0.0.1", user: NSUserName(), port: port, identityFile: folder.appendingPathComponent("client").path)
        let connection = SSHConnection(profile: profile, socket: folder.appendingPathComponent("socket").path)
        let master = Process()
        master.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        master.arguments = ["-o", "UserKnownHostsFile=\(folder.path)/known_hosts", "-o", "StrictHostKeyChecking=yes", "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes"] + connection.interactiveArguments + ["sleep 30"]
        master.standardOutput = logHandle; master.standardError = logHandle
        // Give sshd a chance to bind, then use a bounded retry for the real socket.
        let deadline = Date().addingTimeInterval(5)
        var ready = false
        while Date() < deadline && server.isRunning {
            let result = try await CommandRunner.run("/usr/bin/nc", ["-z", "127.0.0.1", String(port)], timeout: 1)
            if result.status == 0 { ready = true; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(ready, (try? String(contentsOf: log, encoding: .utf8)) ?? "sshd did not start")
        let untrusted = try await CommandRunner.run("/usr/bin/ssh", ["-o", "UserKnownHostsFile=\(folder.path)/missing_hosts", "-o", "StrictHostKeyChecking=yes"] + connection.commandArguments("printf should-not-run"))
        XCTAssertNotEqual(untrusted.status, 0)
        XCTAssertTrue(untrusted.text.contains("Host key verification failed"), untrusted.text)
        try master.run()
        defer { if master.isRunning { master.terminate(); master.waitUntilExit() } }
        while !FileManager.default.fileExists(atPath: connection.socket) && master.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: connection.socket), (try? String(contentsOf: log, encoding: .utf8)) ?? "no SSH socket")
        let source = folder.appendingPathComponent("日本語 ' $(not-a-command).txt")
        let payload = "real SSH / SFTP transfer 日本語\n"
        try payload.write(to: source, atomically: true, encoding: .utf8)
        let paths = try await connection.upload([source])
        XCTAssertEqual(paths.count, 1)
        let copied = try await CommandRunner.run("/usr/bin/ssh", connection.commandArguments("cat -- " + Shell.quote(try XCTUnwrap(paths.first))))
        XCTAssertEqual(copied.status, 0, copied.text)
        XCTAssertEqual(copied.text, payload)
        let remoteDirectory = URL(fileURLWithPath: try XCTUnwrap(paths.first)).deletingLastPathComponent().path
        _ = try await CommandRunner.run("/usr/bin/ssh", connection.commandArguments("rm -rf -- " + Shell.quote(remoteDirectory)))
    }

    private func unusedPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TerminalError.message("socket failed") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw TerminalError.message("bind failed") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { throw TerminalError.message("getsockname failed") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
