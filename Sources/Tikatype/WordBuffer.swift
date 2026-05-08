import Carbon
import Foundation

/// A single recorded keystroke: the physical key and any modifiers held at the time.
struct KeyStroke {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

/// Stores the keystrokes of the word currently being typed.
/// The core insight from Punto: we save (keyCode, modifiers) pairs, NOT characters,
/// so we can re-interpret the same physical key presses in any layout later.
final class WordBuffer {

    private(set) var strokes: [KeyStroke] = []

    func clear() {
        strokes.removeAll(keepingCapacity: true)
    }

    func append(_ stroke: KeyStroke) {
        strokes.append(stroke)
    }

    func removeLastStroke() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    var isEmpty: Bool { strokes.isEmpty }
    var count: Int { strokes.count }

    /// Re-interpret the stored keycodes in the given layout.
    /// Returns nil if any keycode produces no character in that layout.
    func string(using layout: TISInputSource) -> String? {
        var result = ""
        for stroke in strokes {
            guard let ch = DynamicKeyMapping.character(
                forKeyCode: stroke.keyCode,
                modifiers: stroke.modifiers,
                layout: layout
            ) else { return nil }
            result += ch
        }
        return result
    }
}
