import Foundation

public enum SSHConfigDiscovery {
    public static func aliases(at url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")) -> [String] {
        var visited = Set<String>()
        var names = Set<String>()
        func read(_ file: URL, depth: Int) {
            guard depth < 16, visited.insert(file.standardizedFileURL.path).inserted,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) {
                let fields = tokenize(line.replacingOccurrences(of: "=", with: " "))
                guard let keyword = fields.first?.lowercased() else { continue }
                if keyword == "host" {
                    for name in fields.dropFirst() where !name.contains("*") && !name.contains("?") && !name.hasPrefix("!") {
                        if (try? SSHProfile(name: name, host: name).validate()) != nil { names.insert(name) }
                    }
                } else if keyword == "include" {
                    for pattern in fields.dropFirst() {
                        let expanded = (pattern as NSString).expandingTildeInPath
                        let path = expanded.hasPrefix("/") ? expanded : file.deletingLastPathComponent().appendingPathComponent(expanded).path
                        var matches = glob_t()
                        if glob(path, 0, nil, &matches) == 0, let paths = matches.gl_pathv {
                            for i in 0..<Int(matches.gl_pathc) { if let item = paths[i] { read(URL(fileURLWithPath: String(cString: item)), depth: depth + 1) } }
                        }
                        globfree(&matches)
                    }
                }
            }
        }
        read(url, depth: 0)
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private static func tokenize(_ text: String) -> [String] {
        var result: [String] = [], token = "", quote: Character?, escaped = false
        for c in text {
            if escaped { token.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "\"" || c == "'" { quote = c; continue }
            if c == "#" { break }
            if c.isWhitespace { if !token.isEmpty { result.append(token); token = "" } } else { token.append(c) }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }
}

public struct TailscalePeer: Identifiable, Sendable {
    public let name: String
    public let host: String
    public let online: Bool
    public var id: String { "tailscale:" + host }
    public static func decode(_ data: Data) throws -> [TailscalePeer] {
        struct Peer: Decodable { var HostName: String; var DNSName: String?; var TailscaleIPs: [String]?; var Online: Bool? }
        struct Status: Decodable { var Peer: [String: Peer]? }
        return try JSONDecoder().decode(Status.self, from: data).Peer?.values.map {
            let dns = ($0.DNSName ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return TailscalePeer(name: $0.HostName, host: dns.isEmpty ? ($0.TailscaleIPs?.first ?? $0.HostName) : dns, online: $0.Online ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }
    public static func discover() async throws -> [TailscalePeer] {
        let paths = ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return [] }
        let output = try await CommandRunner.run(path, ["status", "--json"])
        guard output.status == 0 else { throw TerminalError.message(output.text) }
        return try decode(output.data)
    }
}
