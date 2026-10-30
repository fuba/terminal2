import Foundation

/// Strips VT control strings without leaking split OSC/DCS payloads into logs.
public struct EscapeFilter {
    private enum State { case text, escape, csi, string, stringEscape, charset }
    private var state: State = .text
    public init() {}
    public mutating func consume(_ data: Data) -> Data {
        var output = Data()
        for byte in data {
            switch state {
            case .text:
                if byte == 0x1b { state = .escape }
                else if byte == 10 || byte == 9 || byte >= 32 && byte != 127 { output.append(byte) }
            case .escape:
                switch byte {
                case 0x5b: state = .csi
                case 0x5d, 0x50, 0x5e, 0x5f, 0x58: state = .string
                case 0x20...0x2f: state = .charset
                default: state = .text
                }
            case .csi:
                if (0x40...0x7e).contains(byte) { state = .text }
                else if byte == 0x1b { state = .escape }
            case .string:
                if byte == 0x07 { state = .text }
                else if byte == 0x1b { state = .stringEscape }
            case .stringEscape:
                state = byte == 0x5c || byte == 0x07 ? .text : (byte == 0x1b ? .stringEscape : .string)
            case .charset:
                if (0x30...0x7e).contains(byte) { state = .text }
            }
        }
        return output
    }
}
