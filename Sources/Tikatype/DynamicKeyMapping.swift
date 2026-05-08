import Carbon
import Foundation

/// Maps keycodes to characters using TIS/UCKeyTranslate for a given layout.
/// This is the foundation for both WordBuffer replay and trigger generation.
final class DynamicKeyMapping {

    static func character(forKeyCode keyCode: CGKeyCode,
                          modifiers: CGEventFlags,
                          layout: TISInputSource) -> String? {
        guard let data = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> String? in
            guard let base = ptr.baseAddress else { return nil }
            let uchrPtr = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var charCount = 0
            let cocoaMods = modifiersToCocoaFlags(modifiers)
            let status = UCKeyTranslate(
                uchrPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                UInt32(cocoaMods >> 8),
                UInt32(LMGetKbdLast()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &charCount,
                &chars
            )
            guard status == noErr, charCount > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: charCount)
        }
    }

    /// Returns a mapping [char → keyCode] for all printable keys in a layout.
    static func charToKeyCode(for layout: TISInputSource) -> [Character: CGKeyCode] {
        var result: [Character: CGKeyCode] = [:]
        for keyCode in CGKeyCode(0)..<CGKeyCode(128) {
            if let s = character(forKeyCode: keyCode, modifiers: [], layout: layout),
               s.count == 1 {
                result[s.first!] = keyCode
            }
        }
        return result
    }

    /// Converts a string typed in `sourceLayout` to what it would produce in `targetLayout`
    /// using the same physical keycodes.
    static func convert(_ text: String,
                        from sourceLayout: TISInputSource,
                        to targetLayout: TISInputSource) -> String? {
        let charToKey = charToKeyCode(for: sourceLayout)
        var result = ""
        for ch in text {
            guard let keyCode = charToKey[ch],
                  let converted = character(forKeyCode: keyCode, modifiers: [], layout: targetLayout) else {
                return nil
            }
            result += converted
        }
        return result
    }

    // MARK: - Private

    private static func modifiersToCocoaFlags(_ flags: CGEventFlags) -> UInt64 {
        var cocoaMods: UInt64 = 0
        if flags.contains(.maskShift)   { cocoaMods |= UInt64(shiftKey) }
        if flags.contains(.maskAlternate) { cocoaMods |= UInt64(optionKey) }
        if flags.contains(.maskControl) { cocoaMods |= UInt64(controlKey) }
        return cocoaMods
    }
}
