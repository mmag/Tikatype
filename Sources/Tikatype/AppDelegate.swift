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
        monitor.onConvertWord   = { [weak self] in self?.convertWord() }
        monitor.onConvertPhrase = { [weak self] in self?.convertPhrase() }
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
        guard let target = targetLayout() else { return }
        TextConverter.convertSelected(from: LayoutManager.currentLayout, to: target)
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        perAppManager.applicationDidActivate(app)
        buffer.clear()
    }

    // MARK: - Conversion

    private func convertWord() {
        guard let target = targetLayout() else { return }
        TextConverter.replaceWord(buffer: buffer, switchingTo: target)
    }

    private func convertPhrase() {
        guard let target = targetLayout() else { return }
        TextConverter.replacePhrase(buffer: buffer, switchingTo: target)
    }

    /// Returns the layout to switch TO based on the stored pair and current layout.
    private func targetLayout() -> TISInputSource? {
        let all       = LayoutManager.availableLayouts
        let currentID = LayoutManager.sourceID(of: LayoutManager.currentLayout)

        if let aID = settings.primaryLayoutID, let bID = settings.secondaryLayoutID {
            let targetID = (currentID == aID) ? bID : aID
            return all.first { LayoutManager.sourceID(of: $0) == targetID }
        }

        return all.first { LayoutManager.sourceID(of: $0) != currentID }
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText     = "Accessibility Permission Required"
        alert.informativeText = "Tikatype needs Accessibility permission to monitor keyboard input. Please grant it in System Settings → Privacy & Security → Accessibility, then relaunch."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}
