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

    private let appVersion = "1.0.1"

    private struct LastConversion {
        let text: String
        let charCount: Int
        let layout1: TISInputSource
        let layout2: TISInputSource
    }
    private var lastConversion: LastConversion?
    private var conversionPending = false

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
        guard beginConversion() else { return }
        guard let (l1, l2) = layoutPair() else { conversionPending = false; return }
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
        case selected(String)
        case unsupported
    }

    private func beginConversion() -> Bool {
        guard !conversionPending else { return false }
        conversionPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.conversionPending = false
        }
        return true
    }

    private func convertWord() {
        guard beginConversion() else { return }
        guard let (l1, l2) = layoutPair() else { conversionPending = false; return }

        // Buffer has strokes: erase via backspaces. For single-line fields (Spotlight, URL bars)
        // use direct AX value write instead — backspaces are unreliable there.
        if !buffer.strokes.isEmpty {
            guard let (converted, target) = TextConverter.computeWord(buffer: buffer, layout1: l1, layout2: l2) else { return }
            let charCount = buffer.currentWordStrokes.count + buffer.trailingSeparatorCount
            lastConversion = LastConversion(text: converted, charCount: charCount, layout1: l1, layout2: l2)
            buffer.clear()
            if let element = focusedSingleLineElement() {
                pasteDirectly(converted, element: element, switchTo: target)
            } else {
                TextConverter.eraseAndPaste(charCount: charCount, converted, switchTo: target)
            }
            return
        }

        // Buffer empty: re-conversion takes priority over AX selection to prevent apps that
        // falsely report all document text as "selected" (e.g. Sublime Text) from triggering
        // a full-document replace.
        if let last = lastConversion {
            reconvert(last)
            return
        }

        if case .selected(let text) = axResult() {
            let target = oppositeLayout(l1, l2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextConverter.pasteConverted(text, layout1: l1, layout2: l2, switchTo: target)
            }
        }
    }

    private func convertPhrase() {
        guard beginConversion() else { return }
        guard let (l1, l2) = layoutPair() else { conversionPending = false; return }

        // Buffer has strokes: erase via backspaces. For single-line fields use direct AX write.
        if !buffer.strokes.isEmpty {
            guard let (converted, charCount, target) = TextConverter.computePhrase(buffer: buffer, layout1: l1, layout2: l2) else { return }
            lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
            buffer.clear()
            if let element = focusedSingleLineElement() {
                pasteDirectly(converted, element: element, switchTo: target)
            } else {
                TextConverter.eraseAndPaste(charCount: charCount, converted, switchTo: target)
            }
            return
        }

        if let last = lastConversion {
            reconvert(last)
            return
        }

        if case .selected(let text) = axResult() {
            let target = oppositeLayout(l1, l2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextConverter.pasteConverted(text, layout1: l1, layout2: l2, switchTo: target)
            }
        }
    }

    private func reconvert(_ last: LastConversion) {
        guard let (l1, l2) = layoutPair() else { return }
        let converted = DynamicKeyMapping.convertBidirectional(last.text, layout1: last.layout1, layout2: last.layout2)
        let target = oppositeLayout(l1, l2)
        lastConversion = LastConversion(text: converted, charCount: converted.count, layout1: l1, layout2: l2)
        if let element = focusedSingleLineElement() {
            pasteDirectly(converted, element: element, switchTo: target)
        } else {
            TextConverter.eraseAndPaste(charCount: last.charCount, converted, switchTo: target)
        }
    }

    private static let singleLineRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox"]

    private func focusedSingleLineElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var cfFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &cfFocused) == .success,
              let focused = cfFocused else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var cfRole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &cfRole) == .success,
              let role = cfRole as? String,
              Self.singleLineRoles.contains(role) else { return nil }
        return element
    }

    private func pasteDirectly(_ text: String, element: AXUIElement, switchTo target: TISInputSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            let len = (text as NSString).length
            var range = CFRangeMake(len, 0)
            if let cfRange = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cfRange)
            }
            LayoutManager.switchTo(target)
        }
    }

    private func axResult() -> AXResult {
        let systemWide = AXUIElementCreateSystemWide()
        var cfFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &cfFocused) == .success,
              let focused = cfFocused else { return .unsupported }
        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var cfSel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &cfSel) == .success,
              let sel = cfSel as? String, !sel.isEmpty else { return .unsupported }
        return .selected(sel)
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
