import AppKit
import Carbon
import CoreGraphics
import Foundation

final class TextConverter {

    static let syntheticTag: Int64 = 0x54494B41  // "TIKA" — marks events posted by us

    private static let backspaceKeyCode: CGKeyCode = 51

    /// Converts the last typed word in the buffer to the opposite layout,
    /// determined by the per-stroke layoutID. Pastes result and switches layout.
    /// Erases the last word via sequential backspaces and pastes the conversion.
    /// Use for multi-line AX-capable fields (Telegram, Notes, etc.) where backspaces are reliable.
    static func replaceWord(buffer: PhraseBuffer,
                            layout1: TISInputSource,
                            layout2: TISInputSource) {
        let wordStrokes = buffer.currentWordStrokes
        let sepStrokes  = buffer.trailingSeparatorStrokes
        let eraseCount  = wordStrokes.count + sepStrokes.count
        guard eraseCount > 0 else { return }

        let id1 = LayoutManager.sourceID(of: layout1)
        let converted = strokesToConverted(wordStrokes, id1: id1, layout1: layout1, layout2: layout2)
                      + strokesToConverted(sepStrokes,  id1: id1, layout1: layout1, layout2: layout2)

        let wordLayoutID = wordStrokes.first?.layoutID
        let targetLayout = (wordLayoutID != nil && wordLayoutID == id1) ? layout2 : layout1

        buffer.clear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            eraseChars(eraseCount) {
                pasteString(converted)
                LayoutManager.switchTo(targetLayout)
            }
        }
    }

    /// Selects all text in the field (Cmd+A) and pastes the converted word.
    /// Use for single-line fields and apps where AX is unavailable (Spotlight, Chrome, etc.)
    /// where backspace simulation is unreliable.
    static func replaceWordSelectAll(buffer: PhraseBuffer,
                                     layout1: TISInputSource,
                                     layout2: TISInputSource) {
        let wordStrokes = buffer.currentWordStrokes
        let sepStrokes  = buffer.trailingSeparatorStrokes
        guard !wordStrokes.isEmpty else { return }

        let id1 = LayoutManager.sourceID(of: layout1)
        let converted = strokesToConverted(wordStrokes, id1: id1, layout1: layout1, layout2: layout2)
                      + strokesToConverted(sepStrokes,  id1: id1, layout1: layout1, layout2: layout2)

        let wordLayoutID = wordStrokes.first?.layoutID
        let targetLayout = (wordLayoutID != nil && wordLayoutID == id1) ? layout2 : layout1

        buffer.clear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            postKey(0, modifiers: .maskCommand, source: src)  // Cmd+A
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                pasteString(converted)
                LayoutManager.switchTo(targetLayout)
            }
        }
    }

    /// Converts everything accumulated in the buffer since the last sentence break.
    /// Each keystroke is converted to the OPPOSITE of the layout it was typed in.
    static func replacePhrase(buffer: PhraseBuffer,
                               layout1: TISInputSource,
                               layout2: TISInputSource) {
        let strokes = buffer.strokes
        guard !strokes.isEmpty else { return }

        let id1 = LayoutManager.sourceID(of: layout1)
        let converted = strokesToConverted(strokes, id1: id1, layout1: layout1, layout2: layout2)

        let lastLayoutID = strokes.last(where: { !$0.isSeparator })?.layoutID ?? strokes.last?.layoutID
        let targetLayout = (lastLayoutID != nil && lastLayoutID == id1) ? layout2 : layout1

        let eraseCount = strokes.count
        buffer.clear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            eraseChars(eraseCount) {
                pasteString(converted)
                LayoutManager.switchTo(targetLayout)
            }
        }
    }

    /// Copies the current text selection, converts layout bidirectionally, and pastes back.
    /// Used by the menu item / ⌥⌃ hotkey — does not rely on the buffer.
    static func convertSelected(layout1: TISInputSource, layout2: TISInputSource,
                                 switchTo targetLayout: TISInputSource) {
        let pasteboard  = NSPasteboard.general
        let saved       = pasteboard.string(forType: .string)
        let beforeCount = pasteboard.changeCount

        let src = CGEventSource(stateID: .hidSystemState)
        postKey(8, modifiers: .maskCommand, source: src)  // Cmd+C

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pasteboard.changeCount != beforeCount,
                  let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
            let converted = DynamicKeyMapping.convertBidirectional(text, layout1: layout1, layout2: layout2)
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            postKey(9, modifiers: .maskCommand, source: src)  // Cmd+V
            LayoutManager.switchTo(targetLayout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let saved { pasteboard.setString(saved, forType: .string) }
            }
        }
    }

    /// Converts `text` bidirectionally, pastes it, and switches layout.
    /// Used when the caller already has the selected text (e.g. from Accessibility API).
    static func pasteConverted(_ text: String,
                                layout1: TISInputSource,
                                layout2: TISInputSource,
                                switchTo targetLayout: TISInputSource) {
        let converted = DynamicKeyMapping.convertBidirectional(text, layout1: layout1, layout2: layout2)
        pasteString(converted)
        LayoutManager.switchTo(targetLayout)
    }

    // MARK: - Private

    private static func strokesToConverted(_ strokes: [KeyStroke],
                                            id1: String?,
                                            layout1: TISInputSource,
                                            layout2: TISInputSource) -> String {
        var result = ""
        for s in strokes {
            let isFromLayout1 = (s.layoutID != nil && s.layoutID == id1)
            let tgtLayout = isFromLayout1 ? layout2 : layout1
            let srcLayout = isFromLayout1 ? layout1 : layout2
            if let ch = DynamicKeyMapping.character(forKeyCode: s.keyCode, modifiers: s.modifiers, layout: tgtLayout) {
                result += ch
            } else if let ch = DynamicKeyMapping.character(forKeyCode: s.keyCode, modifiers: s.modifiers, layout: srcLayout) {
                result += ch
            }
        }
        return result
    }

    // Posts backspaces one at a time with 15 ms gaps, then calls completion after 120 ms.
    // Sequential delivery prevents event coalescing in reactive text fields (e.g. Spotlight).
    private static func eraseChars(_ count: Int, then completion: @escaping () -> Void) {
        guard count > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { completion() }
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        postKey(backspaceKeyCode, source: src)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            eraseChars(count - 1, then: completion)
        }
    }

    private static func pasteString(_ text: String) {
        let pb    = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let src = CGEventSource(stateID: .hidSystemState)
        postKey(9, modifiers: .maskCommand, source: src)  // Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }

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
