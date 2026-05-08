import Carbon
import Foundation

/// Classifies whether a word was typed in the wrong layout.
///
/// Strategy (mirrors Punto's ConversionEngine):
/// 1. Build a set of "triggers" — sequences that are impossible/very rare in a given language
///    when the word is typed on the wrong keyboard layout.
/// 2. On each word, try converting it to the other layout(s). If the converted form
///    hits a trigger, the original word was likely typed in the wrong layout.
///
/// Detection result codes match Punto's internal values for clarity.
enum DetectionResult {
    case correctLayout          // 2 — word looks right in current layout
    case wrongLayout            // 4 — word should be in the other layout
    case ambiguous              // 8 — could be either
}

final class LayoutDetector {

    private var triggers: Set<String> = []

    // MARK: - Setup

    /// Builds triggers by converting high-frequency Russian words through
    /// the "typed on Latin keyboard" transformation.
    func buildTriggers(russianWords: [String],
                       russianLayout: TISInputSource,
                       latinLayout: TISInputSource) {
        var set: Set<String> = []
        for word in russianWords {
            // What does this Russian word look like if the user typed it on a Latin keyboard?
            if let asTypedOnLatin = DynamicKeyMapping.convert(word, from: russianLayout, to: latinLayout) {
                set.insert(asTypedOnLatin.lowercased())
            }
        }
        triggers = set
    }

    // MARK: - Detection

    /// Returns whether `word` (typed in `currentLayout`) looks like it belongs in `otherLayout`.
    func detect(word: String,
                currentLayout: TISInputSource,
                otherLayout: TISInputSource) -> DetectionResult {
        guard !word.isEmpty else { return .correctLayout }

        // Convert the word to what it would produce on the other layout
        guard let converted = DynamicKeyMapping.convert(word, from: currentLayout, to: otherLayout) else {
            return .correctLayout
        }

        let wordLower = word.lowercased()
        let convertedLower = converted.lowercased()

        let currentIsTrigger = triggers.contains(wordLower)
        let convertedIsTrigger = triggers.contains(convertedLower)

        switch (currentIsTrigger, convertedIsTrigger) {
        case (false, true):
            // Current layout produces a trigger word, converted does not — typed in wrong layout
            return .wrongLayout
        case (true, false):
            return .correctLayout
        case (true, true), (false, false):
            // Use bigram/trigram heuristic as a tiebreaker
            return scoreHeuristic(word: wordLower,
                                  converted: convertedLower,
                                  layout: currentLayout,
                                  otherLayout: otherLayout)
        }
    }

    // MARK: - Heuristic tiebreaker

    /// Simple impossible-sequence detector: certain letter combinations can't occur in Russian or English.
    private func scoreHeuristic(word: String,
                                converted: String,
                                layout: TISInputSource,
                                otherLayout: TISInputSource) -> DetectionResult {
        let cyrillicImpossible = ["ьъ", "ъь", "йй", "ыы", "ъъ", "ьь"]
        let latinImpossible    = ["qx", "xq", "jx", "zx"]

        func hits(_ text: String, _ sequences: [String]) -> Int {
            sequences.filter { text.contains($0) }.count
        }

        let isCyrillicWord = word.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }

        if isCyrillicWord {
            // Word is already Cyrillic — check if it has impossible Cyrillic sequences
            if hits(word, cyrillicImpossible) > 0 { return .wrongLayout }
            return .correctLayout
        } else {
            // Word is Latin — check if converting to Cyrillic reduces impossibilities
            let cyrillicHits = hits(converted, cyrillicImpossible)
            let latinHits    = hits(word, latinImpossible)
            if cyrillicHits == 0 && latinHits > 0 { return .wrongLayout }
            return .correctLayout
        }
    }
}
