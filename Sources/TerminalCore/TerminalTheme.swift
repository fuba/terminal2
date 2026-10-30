import Foundation

public struct TerminalTheme: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let foreground: String
    public let background: String
    public let ansi: [String]
    public static let dark = TerminalTheme(id: "dark", name: "ダーク", foreground: "#E2E4E9", background: "#17191E", ansi: ["#252830", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF", "#5C6370", "#FF7A85", "#B1DD8C", "#F5D99A", "#80C7FF", "#DE9CF0", "#7AD3DF", "#F2F3F5"])
    public static let light = TerminalTheme(id: "light", name: "ライト", foreground: "#24262B", background: "#F7F7F5", ansi: ["#24262B", "#A52336", "#36712E", "#806009", "#175DA8", "#80449D", "#126E7A", "#B7B8BC", "#64666B", "#BF3348", "#437C39", "#8A6D16", "#216DB5", "#9056AD", "#1B7D89", "#FFFFFF"])
    public static let midnight = TerminalTheme(id: "midnight", name: "ミッドナイト", foreground: "#D6DAE3", background: "#0D1117", ansi: ["#161B22", "#FF7B72", "#7EE787", "#D29922", "#79C0FF", "#D2A8FF", "#76E3EA", "#B1BAC4", "#6E7681", "#FFA198", "#AFF5B4", "#E3B341", "#A5D6FF", "#E2C5FF", "#B3F0FF", "#F0F6FC"])
    public static let paper = TerminalTheme(id: "paper", name: "ペーパー", foreground: "#35342F", background: "#F1EDE3", ansi: ["#35342F", "#9D3333", "#496F3B", "#866625", "#366689", "#785688", "#3B7474", "#C6C0B4", "#7C786E", "#AD4444", "#5A7D4C", "#94742F", "#477798", "#896798", "#4C8585", "#FCFAF5"])
    public static let monochrome = TerminalTheme(id: "monochrome", name: "モノクロ", foreground: "#E7E7E7", background: "#171717", ansi: ["#171717", "#B0B0B0", "#C0C0C0", "#D0D0D0", "#A8A8A8", "#BABABA", "#CACACA", "#DEDEDE", "#777777", "#CCCCCC", "#D8D8D8", "#E4E4E4", "#C4C4C4", "#D4D4D4", "#E0E0E0", "#FFFFFF"])
    public static let all = [dark, light, midnight, paper, monochrome]
    public func apply(to configuration: inout Configuration) {
        configuration.foreground = foreground; configuration.background = background; configuration.ansiColors = ansi
    }
    public static func matching(_ configuration: Configuration) -> TerminalTheme? {
        all.first { $0.foreground == configuration.foreground && $0.background == configuration.background && ($0.ansi == configuration.ansiColors || configuration.ansiColors.isEmpty && $0.id == dark.id) }
    }
}
