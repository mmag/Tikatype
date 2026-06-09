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
    var onConvertSelection: (() -> Void)?
    var onNewStroke: (() -> Void)?

    // Double-Option: press → release → press (no keyDown between) within threshold
    private var optionIsDown = false
    private var lastOptionReleaseDate: Date?
    private static let doubleOptInterval: TimeInterval = 0.4

    // Ctrl+Shift: fire when both keys are fully RELEASED after being pressed together
    private var prevFlags: CGEventFlags = []
    private var ctrlShiftPending = false

    // Opt+Shift: same fire-on-release pattern
    private var optShiftPending = false

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
            print("Tikatype: failed to create event tap — check Accessibility and Input Monitoring permissions")
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

        // Any real keyDown cancels all pending modifier hotkeys
        lastOptionReleaseDate = nil
        ctrlShiftPending = false
        optShiftPending  = false

        let keyCode   = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags

        if keyCode == 51 { buffer.removeLastStroke(); onNewStroke?(); return }  // Backspace
        if keyCode == 53 { buffer.clear(); onNewStroke?(); return }             // Escape
        if keyCode == 36 { buffer.clear(); onNewStroke?(); return }             // Return → sentence break

        guard !isNavigationKey(keyCode) else { onNewStroke?(); return }

        if modifiers.contains(.maskCommand) || modifiers.contains(.maskControl) {
            buffer.clear()
            onNewStroke?()
            return
        }

        let currentLayoutID = LayoutManager.sourceID(of: LayoutManager.currentLayout)

        if Self.wordSeparators.contains(keyCode) {
            buffer.append(KeyStroke(keyCode: keyCode, modifiers: modifiers, isSeparator: true, layoutID: currentLayoutID))
            return
        }

        // Sentence-ending punctuation clears the phrase, unless the key maps to a letter
        // in the other tracked layout (e.g. "." = "ю" in Russian).
        let ch = DynamicKeyMapping.character(forKeyCode: keyCode, modifiers: modifiers,
                                             layout: LayoutManager.currentLayout)
        if let ch, "!.?".contains(ch) {
            if isLetterInOtherLayout(keyCode: keyCode, modifiers: modifiers) {
                buffer.append(KeyStroke(keyCode: keyCode, modifiers: modifiers, isSeparator: false, layoutID: currentLayoutID))
            } else {
                buffer.clear()
            }
            return
        }

        buffer.append(KeyStroke(keyCode: keyCode, modifiers: modifiers, isSeparator: false, layoutID: currentLayoutID))
    }

    // MARK: - Modifier-key hotkeys

    private func handleFlagsChanged(flags: CGEventFlags) {

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.excludedApps.contains(id) {
            ctrlShiftPending = false
            optShiftPending  = false
            optionIsDown     = false
            lastOptionReleaseDate = nil
            return
        }

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

        // Opt+Ctrl: arm on press, fire on full release, clear double-opt window to avoid false trigger
        let osNow = flags.contains(.maskAlternate) && flags.contains(.maskControl)
            && !flags.contains(.maskCommand) && !flags.contains(.maskShift)

        if osNow { optShiftPending = true }

        if optShiftPending && !flags.contains(.maskAlternate) && !flags.contains(.maskControl) {
            optShiftPending = false
            lastOptionReleaseDate = nil
            onConvertSelection?()
        }

        prevFlags = flags
    }

    // MARK: - Helpers

    private func isNavigationKey(_ keyCode: CGKeyCode) -> Bool {
        let navKeys: Set<CGKeyCode> = [123, 124, 125, 126, 115, 116, 119, 121, 114, 117]
        return navKeys.contains(keyCode) || (keyCode >= 96 && keyCode <= 122)
    }

    private func isLetterInOtherLayout(keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        let currentID = LayoutManager.sourceID(of: LayoutManager.currentLayout)
        let otherIDs  = [settings.primaryLayoutID, settings.secondaryLayoutID]
            .compactMap { $0 }
            .filter { $0 != currentID }
        guard !otherIDs.isEmpty else { return false }
        let all = LayoutManager.availableLayouts
        for layout in all where otherIDs.contains(LayoutManager.sourceID(of: layout) ?? "") {
            if let ch = DynamicKeyMapping.character(forKeyCode: keyCode, modifiers: modifiers, layout: layout),
               ch.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
                return true
            }
        }
        return false
    }
}
