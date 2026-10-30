import Foundation

enum SidebarGeometry {
    struct Layout { let terminal: CGRect; let sidebar: CGRect }
    static func layout(terminal: CGRect, visible: CGRect, width: CGFloat = 252, gap: CGFloat = 8) -> Layout {
        let width = min(width, max(160, visible.width * 0.3))
        var terminal = terminal
        terminal.size.width = min(terminal.width, max(320, visible.width - width - gap))
        terminal.size.height = min(terminal.height, visible.height)
        terminal.origin.y = min(max(terminal.minY, visible.minY), visible.maxY - terminal.height)
        terminal.origin.x = min(max(terminal.minX, visible.minX), visible.maxX - terminal.width)
        var x: CGFloat
        if terminal.minX - width - gap >= visible.minX { x = terminal.minX - width - gap }
        else if terminal.maxX + gap + width <= visible.maxX { x = terminal.maxX + gap }
        else {
            terminal.origin.x = visible.minX + width + gap
            x = visible.minX
        }
        return Layout(terminal: terminal, sidebar: CGRect(x: x, y: terminal.minY, width: width, height: terminal.height))
    }
}
