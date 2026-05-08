import AppKit
import Carbon
import CoreGraphics
import Foundation

final class TextConverter {

    static let syntheticTag: Int64 = 0x54494B41  // "TIKA" — marks events posted by us

    private static let backspaceKeyCode: CGKeyCode = 51

    /// Converts the last typed word in the buffer to targetLayout.
    /// Erases it with backspaces, switches layout, retypes the same physical keys.
    static func replaceWord(buffer: PhraseBuffer, switchingTo targetLayout: TISInputSource) {
        let wordStrokes = buffer.currentWordStrokes
        let sepStrokes  = buffer.trailingSeparatorStrokes
        let eraseCount  = wordStrokes.count + sepStrokes.count
        guard eraseCount > 0 else { return }

        buffer.clear()
        LayoutManager.switchTo(targetLayout)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<eraseCount { postKey(backspaceKeyCode, source: src) }
            for s in wordStrokes    { postKey(s.keyCode, modifiers: s.modifiers, source: src) }
            for s in sepStrokes     { postKey(s.keyCode, modifiers: s.modifiers, source: src) }
        }
    }

    /// Converts everything accumulated in the buffer (since last sentence break) to targetLayout.
    static func replacePhrase(buffer: PhraseBuffer, switchingTo targetLayout: TISInputSource) {
        let strokes = buffer.strokes
        guard !strokes.isEmpty else { return }

        buffer.clear()
        LayoutManager.switchTo(targetLayout)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<strokes.count { postKey(backspaceKeyCode, source: src) }
            for s in strokes           { postKey(s.keyCode, modifiers: s.modifiers, source: src) }
        }
    }

    /// Tries to convert the current selection via Cmd+C; if the clipboard didn't change
    /// (nothing was selected), falls back to converting the last word from the buffer.
    static func convertSelectionOrWord(buffer: PhraseBuffer,
                                       from current: TISInputSource,
                                       to target: TISInputSource) {
        let pb          = NSPasteboard.general
        let beforeCount = pb.changeCount
        let savedText   = pb.string(forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)
        postKey(8, modifiers: .maskCommand, source: src)  // Cmd+C

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if pb.changeCount != beforeCount,
               let copied = pb.string(forType: .string), !copied.isEmpty,
               let converted = DynamicKeyMapping.convert(copied, from: current, to: target) {
                pb.clearContents()
                pb.setString(converted, forType: .string)
                postKey(9, modifiers: .maskCommand, source: src)  // Cmd+V
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pb.clearContents()
                    if let savedText { pb.setString(savedText, forType: .string) }
                }
            } else {
                // Nothing was selected — restore clipboard and convert last word
                pb.clearContents()
                if let savedText { pb.setString(savedText, forType: .string) }
                replaceWord(buffer: buffer, switchingTo: target)
            }
        }
    }

    /// Copies the current text selection, converts layout, and pastes back.
    /// Uses Cmd+C / Cmd+V — does not rely on buffer.
    static func convertSelected(from current: TISInputSource, to target: TISInputSource) {
        let pasteboard = NSPasteboard.general
        let saved      = pasteboard.string(forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)
        postKey(8, modifiers: .maskCommand, source: src)  // Cmd+C

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let text      = pasteboard.string(forType: .string), !text.isEmpty,
                  let converted = DynamicKeyMapping.convert(text, from: current, to: target)
            else { return }

            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            postKey(9, modifiers: .maskCommand, source: src)  // Cmd+V

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let saved { pasteboard.setString(saved, forType: .string) }
            }
        }
    }

    /// Converts `text` and pastes it, replacing the current selection.
    /// Used when the caller already has the selected text (e.g. from Accessibility API).
    static func pasteConverted(_ text: String,
                               from current: TISInputSource,
                               to target: TISInputSource) {
        guard let converted = DynamicKeyMapping.convert(text, from: current, to: target) else { return }
        let pb    = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(converted, forType: .string)
        let src = CGEventSource(stateID: .hidSystemState)
        postKey(9, modifiers: .maskCommand, source: src)  // Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

    // MARK: - Private

    private static func postKey(_ keyCode: CGKeyCode,
                                modifiers: CGEventFlags = [],
                                source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = modifiers
        up.flags   = modifiers
        down.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
