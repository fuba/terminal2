import Foundation

public struct Configuration: Codable, Equatable {
    public var shell = "/bin/zsh"
    public var fontFamily = "SFMono-Regular"
    public var fontSize: Double = 15
    public var scrollback = 10000
    public var columns = 120
    public var rows = 32
    public var opacity: Double = 1
    public var foreground = "#E2E4E9"
    public var background = "#17191E"
    public var optionAsMeta = false
    public var useMetal = true
    public var hotkey = HotkeyConfiguration()
    public var sshProfiles: [SSHProfile] = []
    public var bookmarks: [Bookmark] = []
    public var favorites: [String] = []

    public init() {}
    enum CodingKeys: String, CodingKey { case shell, fontFamily, fontSize, scrollback, columns, rows, opacity, foreground, background, optionAsMeta, useMetal, hotkey, sshProfiles, bookmarks, favorites }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? shell
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? fontFamily
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        scrollback = try c.decodeIfPresent(Int.self, forKey: .scrollback) ?? scrollback
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? columns
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? rows
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? foreground
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? background
        optionAsMeta = try c.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? optionAsMeta
        useMetal = try c.decodeIfPresent(Bool.self, forKey: .useMetal) ?? useMetal
        hotkey = try c.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkey) ?? hotkey
        sshProfiles = try c.decodeIfPresent([SSHProfile].self, forKey: .sshProfiles) ?? []
        bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }

    public func validated() throws -> Configuration {
        guard (8...48).contains(fontSize), (80...1_000_000).contains(scrollback),
              (40...500).contains(columns), (10...200).contains(rows), (0.35...1).contains(opacity),
              Self.isColor(foreground), Self.isColor(background), shell.hasPrefix("/"), !shell.contains("\0") else {
            throw TerminalError.message("設定値が範囲外です。フォント 8〜48 pt、列 40〜500、行 10〜200、色 #RRGGBB を指定してください。")
        }
        for profile in sshProfiles { try profile.validate() }
        guard Set(sshProfiles.map(\.name)).count == sshProfiles.count,
              Set(bookmarks.map(\.name)).count == bookmarks.count else {
            throw TerminalError.message("SSH 接続先・ブックマークの名前は重複しないようにしてください。")
        }
        for bookmark in bookmarks {
            guard !bookmark.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (bookmark.command != nil) != (bookmark.ssh != nil), bookmark.command?.contains("\0") != true else {
                throw TerminalError.message("ブックマークには command と ssh のどちらか一方を指定してください。")
            }
        }
        return self
    }
    public static func isColor(_ value: String) -> Bool {
        value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }
}

public struct HotkeyConfiguration: Codable, Equatable {
    public var enabled = true
    public var modifiers = ["option", "shift"]
    public var key = "v"
    public init() {}
}

public struct Bookmark: Codable, Equatable, Identifiable {
    public var name: String
    public var command: String?
    public var ssh: String?
    public var id: String { "bookmark:" + name }
    public init(name: String, command: String? = nil, ssh: String? = nil) {
        self.name = name; self.command = command; self.ssh = ssh
    }
}

public enum TerminalError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

public enum AppPaths {
    public static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Terminal2")
    public static let config = support.appendingPathComponent("config.json")
    public static let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Terminal2")
    public static func prepare() throws {
        for path in [support, logs] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
    public static func save(_ configuration: Configuration, to url: URL = config) throws {
        let config = try configuration.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func load(from url: URL = config) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)).validated()
    }
}
