import Foundation

public struct SSHProfile: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var host: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var id: String { "ssh:" + name + ":" + host + ":" + (user ?? "") + ":" + (port.map(String.init) ?? "") }
    public init(name: String, host: String, user: String? = nil, port: Int? = nil, identityFile: String? = nil) {
        self.name = name; self.host = host; self.user = user; self.port = port; self.identityFile = identityFile
    }
    public func validate() throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:%")
        guard !host.isEmpty, !host.hasPrefix("-"), host.unicodeScalars.allSatisfy(allowed.contains),
              user == nil || (!user!.isEmpty && !user!.hasPrefix("-") && user!.unicodeScalars.allSatisfy(allowed.contains)),
              port == nil || (1...65535).contains(port!), identityFile?.contains("\0") != true else {
            throw TerminalError.message("SSH のホスト名・ユーザー名・ポートが不正です。")
        }
    }
    public var destination: String { user.map { $0 + "@" + host } ?? host }
}

public struct SSHConnection: Sendable {
    public let profile: SSHProfile
    public let socket: String
    public init(profile: SSHProfile, socket: String) { self.profile = profile; self.socket = socket }
    private var options: [String] {
        var result = ["-o", "ControlPath=" + socket, "-o", "ControlPersist=no", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3"]
        if let identity = profile.identityFile { result += ["-i", (identity as NSString).expandingTildeInPath] }
        return result
    }
    public var interactiveArguments: [String] {
        var result = options + ["-o", "ControlMaster=yes", "-tt"]
        if let port = profile.port { result += ["-p", String(port)] }
        return result + ["--", profile.destination]
    }
    public func commandArguments(_ command: String) -> [String] {
        var result = options + ["-o", "ControlMaster=no", "-o", "BatchMode=yes", "-o", "RequestTTY=no", "-o", "RemoteCommand=none"]
        if let port = profile.port { result += ["-p", String(port)] }
        return result + ["--", profile.destination, command]
    }
    public func upload(_ urls: [URL]) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: socket) else {
            throw TerminalError.message("SSH 接続の認証が完了してから貼り付けてください。")
        }
        let temporary = try await CommandRunner.run("/usr/bin/ssh", commandArguments("umask 077; mktemp -d /tmp/terminal2.XXXXXXXX"))
        let directory = temporary.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard temporary.status == 0, directory.range(of: "^/tmp/terminal2\\.[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw TerminalError.message("リモートの保存先を作成できませんでした。\n" + temporary.text)
        }
        var paths: [String] = []
        for (index, url) in urls.enumerated() {
            // Generated names avoid remote-shell and SFTP path ambiguity.
            let name = String(index + 1) + "-" + url.lastPathComponent.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? String($0) : "_" }.joined()
            let path = directory + "/" + name
            var args = options + ["-o", "BatchMode=yes", "-o", "RequestTTY=no", "-o", "RemoteCommand=none", "-r"]
            if let port = profile.port { args += ["-P", String(port)] }
            let host = profile.host.contains(":") ? "[\(profile.host)]" : profile.host
            let destination = profile.user.map { $0 + "@" + host } ?? host
            args += ["--", url.path, destination + ":" + path]
            let result = try await CommandRunner.run("/usr/bin/scp", args, timeout: 300)
            guard result.status == 0 else { throw TerminalError.message("アップロードに失敗しました。\n" + result.text) }
            paths.append(path)
        }
        return paths
    }
}
