import AppKit
import TerminalCore
import SwiftTerm

private var crashDescriptor: Int32 = -1

enum Diagnostics {
    static func install() {
        setenv("SWIFTTERM_PROFILE_STATS", "1", 0)
        try? AppPaths.prepare()
        crashDescriptor = open(AppPaths.logs.appendingPathComponent("crash.log").path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        NSSetUncaughtExceptionHandler { exception in
            let message = "\(Date()) \(exception.name.rawValue): \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))\n"
            message.withCString { pointer in _ = Darwin.write(crashDescriptor, pointer, strlen(pointer)) }
        }
        for number in [SIGABRT, SIGSEGV, SIGBUS, SIGILL] {
            signal(number) { value in
                // Only async-signal-safe operations are allowed here.
                let message: StaticString = "Terminal2 fatal signal; inspect macOS DiagnosticReports for the stack.\n"
                _ = Darwin.write(crashDescriptor, message.utf8Start, message.utf8CodeUnitCount)
                signal(value, SIG_DFL)
                raise(value)
            }
        }
        log("Launch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "development")")
    }

    static func recordPerformance() {
        let threshold = Double(ProcessInfo.processInfo.environment["TERMINAL_SLOW_FRAME_MS"] ?? "16") ?? 16
        let slow = TerminalProfiling.summaries().filter { $0.maxMs > threshold }
        if !slow.isEmpty { log("\n" + TerminalProfiling.report(summaries: slow), file: "perf.log") }
        TerminalProfiling.reset()
    }

    static func log(_ message: String, file: String = "app.log") {
        let path = AppPaths.logs.appendingPathComponent(file).path
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        data.withUnsafeBytes { if let base = $0.baseAddress { _ = Darwin.write(fd, base, $0.count) } }
    }
}

final class SessionLog {
    let url: URL
    private let handle: FileHandle
    private var filter = EscapeFilter()
    init(id: UUID) throws {
        url = AppPaths.logs.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970))-\(id.uuidString.prefix(8)).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw TerminalError.message("セッションログを作成できませんでした。")
        }
        handle = try FileHandle(forWritingTo: url)
        _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
        try handle.write(contentsOf: Data("=== Session started \(Date()) ===\n".utf8))
    }
    func append(_ bytes: Data) throws { try handle.write(contentsOf: filter.consume(bytes)) }
    deinit {
        try? handle.write(contentsOf: Data("\n=== Session ended \(Date()) ===\n".utf8))
        try? handle.close()
    }
}
