import AppKit
import Carbon
import CoreGraphics
import Foundation

/// Installs a CGEventTap to intercept all keyboard events.
/// Classifies each keycode as: character, backspace, word-terminator, or ignored.
/// Feeds the WordBuffer and triggers AutoCorrector.
final class KeyboardMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let buffer: WordBuffer
    private let corrector: AutoCorrector
    private let settings: SettingsManager

    // Word-ending characters (space, return, tab, common punctuation)
    private static let wordTerminators: Set<CGKeyCode> = [
        36,  // Return
        48,  // Tab
        49,  // Space
    ]

    // Printable-ish key range — anything below 0x80 and not a modifier/function key
    private static let ignoredKeyCodes: Set<CGKeyCode> = [
        51,  // Delete/Backspace — handled separately
        53,  // Escape
        117, // Forward Delete
        // Arrow keys, F-keys, etc. handled by isNavigationKey()
    ]

    init(buffer: WordBuffer, corrector: AutoCorrector, settings: SettingsManager) {
        self.buffer   = buffer
        self.corrector = corrector
        self.settings  = settings
    }

    // MARK: - Lifecycle

    func start() {
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,           // passive — we don't block events
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )
        guard let tap = eventTap else {
            print("Tikatype: failed to create event tap — check Accessibility permission")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }

        // Ignore if current app is excluded
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.excludedApps.contains(bundleID) {
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags

        // Ignore modifier-only events and navigation keys
        guard !isModifierOnly(modifiers), !isNavigationKey(keyCode) else { return }

        if keyCode == 51 {  // Backspace
            buffer.removeLastStroke()
            return
        }

        if Self.wordTerminators.contains(keyCode) {
            corrector.onWordEnd()
            buffer.clear()
            return
        }

        // Treat Cmd/Ctrl shortcuts as word breaks without starting a new word
        if modifiers.contains(.maskCommand) || modifiers.contains(.maskControl) {
            buffer.clear()
            return
        }

        if Self.ignoredKeyCodes.contains(keyCode) { return }

        // It's a printable character
        let stroke = KeyStroke(keyCode: keyCode, modifiers: modifiers)
        buffer.append(stroke)
        corrector.onCharacter()
    }

    // MARK: - Helpers

    private func isNavigationKey(_ keyCode: CGKeyCode) -> Bool {
        // Arrow keys: 123–126, F-keys: 122 and below typical range, PageUp/Down: 116/121, Home/End: 115/119
        let navKeys: Set<CGKeyCode> = [123, 124, 125, 126, 115, 116, 119, 121, 114, 117]
        return navKeys.contains(keyCode) || (keyCode >= 96 && keyCode <= 122)
    }

    private func isModifierOnly(_ flags: CGEventFlags) -> Bool {
        // If ONLY modifier bits are set (no actual character flags), it's a bare modifier press
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift,
                                          .maskSecondaryFn, .maskNumericPad]
        return modifierMask.contains(flags) && flags.rawValue & 0xFF_FFFF == 0
    }
}
