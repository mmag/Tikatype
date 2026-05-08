import Carbon
import Foundation

/// Enumerates and switches between keyboard input sources.
final class LayoutManager {

    /// Returns all enabled keyboard layouts (both Latin and Cyrillic).
    static var availableLayouts: [TISInputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceIsEnabled as CFString: true,
            kTISPropertyInputSourceCategory as CFString: kTISCategoryKeyboardInputSource as String
        ]
        guard let cfArray = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }
        return (0..<CFArrayGetCount(cfArray)).compactMap { i in
            guard let ptr = CFArrayGetValueAtIndex(cfArray, i) else { return nil }
            return Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
        }
    }

    /// The currently active input source.
    static var currentLayout: TISInputSource {
        TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    /// Switches to the given input source on the main thread.
    static func switchTo(_ layout: TISInputSource) {
        if Thread.isMainThread {
            TISSelectInputSource(layout)
        } else {
            DispatchQueue.main.async { TISSelectInputSource(layout) }
        }
    }

    /// Switches to the first available layout that is not the current one.
    static func switchToAlternate() {
        let current = currentLayout
        let currentID = sourceID(of: current)
        for layout in availableLayouts where sourceID(of: layout) != currentID {
            switchTo(layout)
            return
        }
    }

    static func sourceID(of layout: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(layout, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Returns true if layout appears to produce Cyrillic characters.
    static func isCyrillic(_ layout: TISInputSource) -> Bool {
        guard let langs = TISGetInputSourceProperty(layout, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let arr = Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as [AnyObject]
        return arr.contains { ($0 as? String)?.hasPrefix("ru") == true }
    }

    /// Returns true if layout appears to produce Latin (ASCII) characters.
    static func isLatin(_ layout: TISInputSource) -> Bool {
        return !isCyrillic(layout)
    }
}
