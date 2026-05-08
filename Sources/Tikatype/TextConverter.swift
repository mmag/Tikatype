import Carbon
import CoreGraphics
import Foundation

/// Replaces the current word by:
/// 1. Sending N backspace keystrokes to erase it.
/// 2. Replaying the stored keystrokes (same physical keys) after switching to the target layout.
///
/// This mirrors Punto's `postEventsFromBuffer:type:` exactly — it does NOT use the clipboard.
final class TextConverter {

    private static let backspaceKeyCode: CGKeyCode = 51  // kVK_Delete

    /// Erases `count` characters and types the contents of `buffer` using `targetLayout`.
    ///
    /// - Parameters:
    ///   - buffer: The physical keystrokes of the word that was typed.
    ///   - count: How many characters to erase (usually `buffer.count`).
    ///   - targetLayout: The layout to switch to before replaying.
    static func replaceWord(buffer: WordBuffer,
                            eraseCount count: Int,
                            switchingTo targetLayout: TISInputSource) {
        // Switch layout first so the replayed events produce characters in the new layout
        LayoutManager.switchTo(targetLayout)

        // Small delay to let the layout switch settle before we start typing
        Thread.sleep(forTimeInterval: 0.05)

        let source = CGEventSource(stateID: .hidSystemState)

        // Post N backspaces
        for _ in 0..<count {
            postKey(keyCode: backspaceKeyCode, source: source)
        }

        // Replay the original keystrokes — same physical keys, different layout active
        for stroke in buffer.strokes {
            postKey(keyCode: stroke.keyCode, modifiers: stroke.modifiers, source: source)
        }
    }

    // MARK: - Private

    private static func postKey(keyCode: CGKeyCode,
                                modifiers: CGEventFlags = [],
                                source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = modifiers
        up.flags   = modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
