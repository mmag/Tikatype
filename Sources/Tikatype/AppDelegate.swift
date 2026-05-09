import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings      = SettingsManager()
    private let buffer        = PhraseBuffer()
    private let perAppManager = PerAppLayoutManager()
    private var monitor: KeyboardMonitor!
    private var statusItem: NSStatusItem?
    private var settingsWC: SettingsWindowController?

    private let appVersion = "1.0"

    private struct LastConversion {
        let text: String
        let charCount: Int
        let layout1: TISInputSource
        let layout2: TISInputSource
    }
    private var lastConversion: LastConversion?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        initLayoutDefaults()
        setupComponents()
        setupStatusBar()
        setupAppActivationTracking()
        checkAccessibilityPermission()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Setup

    private func initLayoutDefaults() {
        guard settings.primaryLayoutID == nil else { return }
        let all = LayoutManager.availableLayouts
        settings.primaryLayoutID   = all.first(where: LayoutManager.isCyrillic).flatMap { LayoutManager.sourceID(of: $0) }
                                  ?? all.first.flatMap { LayoutManager.sourceID(of: $0) }
        settings.secondaryLayoutID = all.first(where: LayoutManager.isLatin).flatMap { LayoutManager.sourceID(of: $0) }
                                  ?? (all.count > 1 ? LayoutManager.sourceID(of: all[1]) : nil)
    }

    private func setupComponents() {
        monitor = KeyboardMonitor(buffer: buffer, settings: settings)
        monitor.onConvertWord      = { [weak self] in self?.convertWord() }
        monitor.onConvertPhrase    = { [weak self] in self?.convertPhrase() }
        monitor.onConvertSelection = { [weak self] in self?.convertSelectionAction() }
        monitor.onNewStroke        = { [weak self] in self?.lastConversion = nil }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "character.cursor.ibeam",
                               accessibilityDescription: "Tikatype") {
            image.isTemplate = true
            statusItem?.button?.image = image
        }

        let menu = NSMenu()
        menu.addItem(withTitle: L10n.menuAbout,    action: #selector(showAbout),    keyEquivalent: "")
        menu.addItem(withTitle: L10n.menuSettings, action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.menuConvertSelection,
                     action: #selector(convertSelectionAction),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.menuQuit,
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem?.menu = menu
    }

    private func setupAppActivationTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - Menu actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText    = "Tikatype"
        alert.informativeText = "\(L10n.aboutVersion) \(appVersion)\n\n\(L10n.aboutDescription)"
        alert.addButton(withTitle: L10n.aboutOK)
        if let img = NSImage(systemSymbolName: "character.cursor.ibeam",
                             accessibilityDescription: nil) {
            alert.icon = img
        }
        alert.runModal()
    }

    @objc private func showSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController(settings: settings) }
        settingsWC?.show()
    }

    @objc private func convertSelectionAction() {
        guard let (l1, l2) = layoutPair() else { return }
        TextConverter.convertSelected(layout1: l1, layout2: l2, switchTo: oppositeLayout(l1, l2))
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        perAppManager.applicationDidActivate(app)
        buffer.clear()
    }

    // MARK: - Conversion

    private enum AXResult {
        case selected(String)           // has selection text → pasteConverted
        case emptyMultiLine             // AX works, no selection, multi-line → backspaces safe
        case emptySingleLine(AXUIElement) // AX works, no selection, single-line → AX select + paste
        case unsupported                // AX attribute not available → Cmd+A
    }

    private func convertWord() {
        guard let (l1, l2) = layoutPair() else { return }

        let ax = axResult()

        if case .selected(let text) = ax {
            lastConversion = nil
            let target = oppositeLayout(l1, l2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextConverter.pasteConverted(text, layout1: l1, layout2: l2, switchTo: target)
            }
            return
        }

        if buffer.strokes.isEmpty, let last = lastConversion {
            reconvert(last, ax: ax)
            return
        }

        lastConversion = nil
        switch ax {
        case .emptyMultiLine:
            TextConverter.replaceWord(buffer: buffer, layout1: l1, layout2: l2) { [weak self] converted in
                self?.lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
            }
        case .emptySingleLine(let element):
            guard let (converted, target) = TextConverter.computeWord(buffer: buffer, layout1: l1, layout2: l2) else { return }
            lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
            buffer.clear()
            axSelectAndPaste(converted, element: element, switchTo: target)
        case .unsupported:
            TextConverter.replaceWordSelectAll(buffer: buffer, layout1: l1, layout2: l2) { [weak self] converted in
                self?.lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
            }
        case .selected:
            break
        }
    }

    private func convertPhrase() {
        guard let (l1, l2) = layoutPair() else { return }

        if buffer.strokes.isEmpty, let last = lastConversion {
            reconvert(last, ax: axResult())
            return
        }

        TextConverter.replacePhrase(buffer: buffer, layout1: l1, layout2: l2) { [weak self] converted in
            self?.lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
        }
    }

    private func reconvert(_ last: LastConversion, ax: AXResult) {
        guard let (l1, l2) = layoutPair() else { return }
        let converted = DynamicKeyMapping.convertBidirectional(last.text, layout1: last.layout1, layout2: last.layout2)
        let target = oppositeLayout(l1, l2)
        lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
        switch ax {
        case .emptyMultiLine:
            TextConverter.eraseAndPaste(charCount: last.charCount, converted, switchTo: target)
        case .emptySingleLine(let element):
            axSelectAndPaste(converted, element: element, switchTo: target)
        default:
            TextConverter.selectAllAndPaste(converted, switchTo: target)
        }
    }

    // Writes converted text directly via AX kAXValueAttribute (no clipboard, no keyboard events).
    // Falls back to AX-select-range + paste if the field doesn't allow direct write.
    private func axSelectAndPaste(_ text: String, element: AXUIElement, switchTo target: TISInputSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let writeResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)

            if writeResult == .success {
                let len = (text as NSString).length
                var range = CFRangeMake(len, 0)
                if let cfRange = AXValueCreate(.cfRange, &range) {
                    AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cfRange)
                }
                LayoutManager.switchTo(target)
                return
            }
            // Fallback: select all via AX range, then paste via clipboard
            var cfVal: CFTypeRef?
            let selLen: CFIndex
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &cfVal) == .success,
               let val = cfVal as? String { selLen = val.utf16.count } else { selLen = 999 }
            var selRange = CFRangeMake(0, selLen)
            if let cfRange = AXValueCreate(.cfRange, &selRange) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cfRange)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextConverter.paste(text, switchTo: target)
            }
        }
    }

    private func axResult() -> AXResult {
        // Use system-wide focused element so Spotlight (not in frontmostApplication) is handled correctly.
        let systemWide = AXUIElementCreateSystemWide()
        var cfFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &cfFocused) == .success,
              let focused = cfFocused else { return .unsupported }
        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var cfRole: CFTypeRef?
        let role: String?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &cfRole) == .success {
            role = cfRole as? String
        } else {
            role = nil
        }

        var cfSel: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &cfSel)
        let sel = selResult == .success ? (cfSel as? String ?? "") : nil

        guard selResult == .success else { return .unsupported }
        guard let selStr = sel, selStr.isEmpty else { return .selected(sel ?? "") }

        return role == "AXTextArea" ? .emptyMultiLine : .emptySingleLine(element)
    }

    private func oppositeLayout(_ l1: TISInputSource, _ l2: TISInputSource) -> TISInputSource {
        let currentID = LayoutManager.sourceID(of: LayoutManager.currentLayout)
        return (currentID == LayoutManager.sourceID(of: l1)) ? l2 : l1
    }

    private func layoutPair() -> (TISInputSource, TISInputSource)? {
        let all = LayoutManager.availableLayouts
        guard let aID = settings.primaryLayoutID,
              let bID = settings.secondaryLayoutID,
              let a = all.first(where: { LayoutManager.sourceID(of: $0) == aID }),
              let b = all.first(where: { LayoutManager.sourceID(of: $0) == bID })
        else { return nil }
        return (a, b)
    }

    // MARK: - Permissions

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            showPermissionAlert(
                title: "Accessibility Permission Required",
                body: "Tikatype needs Accessibility permission to read text fields. Please grant it in System Settings → Privacy & Security → Accessibility, then relaunch.",
                url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
            showPermissionAlert(
                title: "Input Monitoring Permission Required",
                body: "Tikatype needs Input Monitoring permission to capture keyboard shortcuts. Please grant it in System Settings → Privacy & Security → Input Monitoring, then relaunch.",
                url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
        }
    }

    private func showPermissionAlert(title: String, body: String, url: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = body
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: url)!)
        }
    }
}
