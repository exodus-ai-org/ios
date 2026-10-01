import SwiftUI

/// SVG path data → `Path`, for the art ported from the approved mockups: M L H V C S Q Z, absolute and relative, with
/// implicit repeats and compact numbers ("0-13"). Arcs are not used by the art; parsing stops at anything unknown.
public enum SVGPath {
    public static func path(_ data: String) -> Path {
        var path = Path()
        var scanner = Tokens(data)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var command: Character?

        while let next = scanner.peekCommand() ?? command {
            if scanner.peekCommand() != nil { scanner.skipCommand() }
            let relative = next.isLowercase
            let base = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            var reflected: CGPoint?
            switch next.uppercased().first! {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                command = relative ? "l" : "L"  // further pairs are lines
                continue
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                reflected = c2
                current = p
            case "S":
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                reflected = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
            case "Z":
                path.closeSubpath()
                current = start
                command = nil
                lastCubicControl = nil
                continue
            default:
                return path
            }
            lastCubicControl = reflected
            command = next
            if scanner.atEnd { break }
        }
        return path
    }

    /// Reads commands and numbers from path data.
    struct Tokens {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        var atEnd: Bool {
            var j = i
            while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n" { j += 1 }
            return j >= chars.count
        }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        mutating func peekCommand() -> Character? {
            skipSeparators()
            guard i < chars.count, chars[i].isLetter else { return nil }
            return chars[i]
        }

        mutating func skipCommand() { i += 1 }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var j = i
            if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 }
            var sawDot = false
            var sawDigit = false
            while j < chars.count {
                if chars[j].isNumber {
                    sawDigit = true
                } else if chars[j] == "." && !sawDot {
                    sawDot = true
                } else {
                    break
                }
                j += 1
            }
            guard sawDigit, let value = Double(String(chars[i..<j])) else { return nil }
            i = j
            return CGFloat(value)
        }
    }
}
