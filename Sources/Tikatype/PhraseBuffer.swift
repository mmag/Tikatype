import Carbon
import Foundation

struct KeyStroke {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let isSeparator: Bool   // space or tab — word boundary inside phrase
    let layoutID: String?   // TIS source ID of the layout active when this key was pressed
}

/// Accumulates keystrokes since the last sentence terminator (. ! ? \n).
/// Word separators (space, tab) are stored but mark word boundaries.
final class PhraseBuffer {

    private(set) var strokes: [KeyStroke] = []

    func clear() { strokes.removeAll(keepingCapacity: true) }
    func append(_ stroke: KeyStroke) { strokes.append(stroke) }
    func removeLastStroke() { if !strokes.isEmpty { strokes.removeLast() } }

    var isEmpty: Bool { strokes.isEmpty }
    var count: Int { strokes.count }

    /// Strokes of the last typed word, with trailing separators trimmed.
    var currentWordStrokes: [KeyStroke] {
        var end = strokes.count
        while end > 0 && strokes[end - 1].isSeparator { end -= 1 }
        guard end > 0 else { return [] }
        var start = end - 1
        while start > 0 && !strokes[start - 1].isSeparator { start -= 1 }
        return Array(strokes[start..<end])
    }

    var trailingSeparatorCount: Int {
        var n = 0, i = strokes.count - 1
        while i >= 0 && strokes[i].isSeparator { n += 1; i -= 1 }
        return n
    }

    var trailingSeparatorStrokes: [KeyStroke] {
        let n = trailingSeparatorCount
        return n > 0 ? Array(strokes.suffix(n)) : []
    }
}
