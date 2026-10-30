import Foundation
import Darwin

public struct CommandOutput: Sendable {
    public let data: Data
    public let status: Int32
    public var text: String { String(decoding: data, as: UTF8.self) }
}

public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15, outputLimit: Int = 8 * 1024 * 1024) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    guard !([executable] + arguments).contains(where: { $0.contains("\0") }) else {
                        throw TerminalError.message("コマンドの引数に NUL 文字は使用できません。")
                    }
                    var descriptors: [Int32] = [0, 0]
                    guard pipe(&descriptors) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    defer { close(descriptors[0]) }
                    _ = fcntl(descriptors[0], F_SETFD, FD_CLOEXEC)
                    _ = fcntl(descriptors[1], F_SETFD, FD_CLOEXEC)
                    var actions: posix_spawn_file_actions_t?
                    var attributes: posix_spawnattr_t?
                    posix_spawn_file_actions_init(&actions)
                    posix_spawnattr_init(&attributes)
                    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
                    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
                    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
                    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
                    posix_spawn_file_actions_addclose(&actions, descriptors[0])
                    posix_spawn_file_actions_addclose(&actions, descriptors[1])
                    // A separate group lets timeouts stop scp's ssh child and ProxyCommand descendants.
                    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
                    posix_spawnattr_setpgroup(&attributes, 0)
                    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
                    let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
                    defer { argv.forEach { free($0) }; environment.forEach { free($0) } }
                    var pid: pid_t = 0
                    let result = argv.withUnsafeBufferPointer { argv in
                        environment.withUnsafeBufferPointer { environment in
                            posix_spawn(&pid, executable, &actions, &attributes, argv.baseAddress!, environment.baseAddress!)
                        }
                    }
                    close(descriptors[1])
                    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
                    let state = CommandState(pid: pid)
                    let deadline = DispatchWorkItem { state.stop(reason: "コマンドがタイムアウトしました") }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    // Drain before waiting; a pipe can fill before the child exits.
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 32768)
                    while true {
                        let count = Darwin.read(descriptors[0], &buffer, buffer.count)
                        if count == 0 { break }
                        if count < 0 { if errno == EINTR { continue }; state.stop(reason: "出力を読み込めませんでした"); break }
                        if data.count + count > outputLimit { state.stop(reason: "コマンドの出力が上限を超えました") }
                        else { data.append(contentsOf: buffer.prefix(count)) }
                    }
                    var waitStatus: Int32 = 0
                    while !state.reap(status: &waitStatus) { Thread.sleep(forTimeInterval: 0.01) }
                    deadline.cancel()
                    if let reason = state.reason { throw TerminalError.message(reason + ": " + URL(fileURLWithPath: executable).lastPathComponent) }
                    let status = waitStatus & 0x7f == 0 ? (waitStatus >> 8) & 0xff : 128 + (waitStatus & 0x7f)
                    continuation.resume(returning: CommandOutput(data: data, status: status))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private final class CommandState: @unchecked Sendable {
    private let lock = NSLock()
    private let pid: pid_t
    private var active = true
    private(set) var reason: String?
    init(pid: pid_t) { self.pid = pid }
    func stop(reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        self.reason = self.reason ?? reason
        kill(-pid, SIGKILL)
    }
    func reap(status: inout Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid || result < 0 && errno != EINTR { active = false; return true }
        return false
    }
}

public enum Shell {
    public static func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func available() -> [String] {
        var paths = ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/opt/homebrew/bin/nu", "/opt/homebrew/bin/pwsh"]
        if let shells = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            paths += shells.components(separatedBy: .newlines).filter { $0.hasPrefix("/") }
        }
        var seen = Set<String>()
        return paths.filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
    }
}
