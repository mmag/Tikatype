import Carbon
import Foundation

/// Decides when and how to correct layout, then triggers TextConverter.
///
/// Two correction modes (ported from Punto's PuntoSwitcherCore):
/// 1. Full-word correction — fires after a word-ending character (space, punctuation).
/// 2. Real-time correction — fires after every character while word is still being typed.
final class AutoCorrector {

    var isEnabled: Bool = true

    private let detector: LayoutDetector
    private let buffer: WordBuffer
    private let settings: SettingsManager

    init(detector: LayoutDetector, buffer: WordBuffer, settings: SettingsManager) {
        self.detector = detector
        self.buffer   = buffer
        self.settings = settings
    }

    // MARK: - Entry points called by KeyboardMonitor

    /// Called after the user types a word terminator (space, Return, punctuation).
    /// Mirrors `autocorrectWordLayout:withEvent:` from PuntoSwitcherCore.
    func onWordEnd() {
        guard isEnabled, !buffer.isEmpty else { return }
        guard let (currentLayout, otherLayout) = layoutPair() else { return }

        let result = detector.detect(
            word: buffer.string(using: currentLayout) ?? "",
            currentLayout: currentLayout,
            otherLayout: otherLayout
        )

        if result == .wrongLayout {
            correctWord(from: currentLayout, to: otherLayout)
        }

        buffer.clear()
    }

    /// Called after every character keystroke while the word is still live.
    /// Mirrors `autocorrectPartialWordLayout` from PuntoSwitcherCore.
    /// Only fires if real-time correction is turned on in settings.
    func onCharacter() {
        guard isEnabled, settings.realtimeCorrection, !buffer.isEmpty else { return }
        guard let (currentLayout, otherLayout) = layoutPair() else { return }

        guard let word = buffer.string(using: currentLayout) else { return }

        let result = detector.detect(
            word: word,
            currentLayout: currentLayout,
            otherLayout: otherLayout
        )

        if result == .wrongLayout {
            correctWord(from: currentLayout, to: otherLayout)
            // After correction the buffer is still intact — TextConverter replayed it in new layout,
            // so we don't clear: the word is continuing in the new layout.
        }
    }

    // MARK: - Correction

    private func correctWord(from current: TISInputSource, to target: TISInputSource) {
        let count = buffer.count
        TextConverter.replaceWord(buffer: buffer, eraseCount: count, switchingTo: target)
    }

    // MARK: - Helpers

    private func layoutPair() -> (current: TISInputSource, other: TISInputSource)? {
        let current = LayoutManager.currentLayout
        let all = LayoutManager.availableLayouts
        guard all.count >= 2 else { return nil }
        guard let other = all.first(where: {
            LayoutManager.sourceID(of: $0) != LayoutManager.sourceID(of: current)
        }) else { return nil }
        return (current, other)
    }
}
