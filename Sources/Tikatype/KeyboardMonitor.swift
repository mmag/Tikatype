import AppKit
import Carbon
import CoreGraphics
import Foundation

final class KeyboardMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let buffer: PhraseBuffer
    private let settings: SettingsManager

    var onConvertWord: (() -> Void)?
    var onConvertPhrase: (() -> Void)?

    // Double-Option: press → release → press (no keyDown between) within threshold
    private var optionIsDown = false
    private var lastOptionReleaseDate: Date?
    private static let doubleOptInterval: TimeInterval = 0.4

    // Ctrl+Shift: fire when both keys are fully RELEASED after being pressed together
    private var prevFlags: CGEventFlags = []
    private var ctrlShiftPending = false

    private static let wordSeparators: Set<CGKeyCode> = [49, 48]  // Space, Tab

    init(buffer: PhraseBuffer, settings: SettingsManager) {
        self.buffer   = buffer
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)     |
            (1 << CGEventType.keyUp.rawValue)       |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    .handle(type: type, event: event)
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

    // MARK: - Event dispatch

    private func handle(type: CGEventType, event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != TextConverter.syntheticTag else { return }

        if type == .flagsChanged {
            handleFlagsChanged(flags: event.flags)
            return
        }

        guard type == .keyDown else { return }

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.excludedApps.contains(id) { return }

        // Any real keyDown cancels the pending double-opt window
        lastOptionReleaseDate = nil

        let keyCode   = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags

        if keyCode == 51 { buffer.removeLastStroke(); return }  // Backspace
        if keyCode == 53 { buffer.clear(); return }             // Escape
        if keyCode == 36 { buffer.clear(); return }             // Return → sentence break

        guard !isNavigationKey(keyCode) else { return }

        if modifiers.contains(.maskCommand) || modifiers.contains(.maskControl) {
            buffer.clear()
            return
        }

        if Self.wordSeparators.contains(keyCode) {
            buffer.append(KeyStroke(keyCode: keyCode, modifiers: modifiers, isSeparator: true))
            return
        }

        // Sentence-ending punctuation clears the phrase
        let ch = DynamicKeyMapping.character(forKeyCode: keyCode, modifiers: modifiers,
                                             layout: LayoutManager.currentLayout)
        if let ch, "!.?".contains(ch) { buffer.clear(); return }

        buffer.append(KeyStroke(keyCode: keyCode, modifiers: modifiers, isSeparator: false))
    }

    // MARK: - Modifier-key hotkeys

    private func handleFlagsChanged(flags: CGEventFlags) {

        // Double-Option
        let optNow = flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskShift)

        if optNow && !optionIsDown {
            if let rel = lastOptionReleaseDate,
               Date().timeIntervalSince(rel) <= Self.doubleOptInterval {
                lastOptionReleaseDate = nil
                onConvertPhrase?()
            }
        } else if !optNow && optionIsDown {
            lastOptionReleaseDate = Date()
        }
        optionIsDown = optNow

        // Ctrl+Shift: arm on press, fire on full release (so Cmd+C/V go out with no modifiers held)
        let csNow = flags.contains(.maskControl) && flags.contains(.maskShift)
            && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)

        if csNow { ctrlShiftPending = true }

        if ctrlShiftPending && !flags.contains(.maskControl) && !flags.contains(.maskShift) {
            ctrlShiftPending = false
            onConvertWord?()
        }

        prevFlags = flags
    }

    // MARK: - Helpers

    private func isNavigationKey(_ keyCode: CGKeyCode) -> Bool {
        let navKeys: Set<CGKeyCode> = [123, 124, 125, 126, 115, 116, 119, 121, 114, 117]
        return navKeys.contains(keyCode) || (keyCode >= 96 && keyCode <= 122)
    }
}
