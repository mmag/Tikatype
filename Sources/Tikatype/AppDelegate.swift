import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings      = SettingsManager()
    private let buffer        = PhraseBuffer()
    private let perAppManager = PerAppLayoutManager()
    private var monitor: KeyboardMonitor!
    private var statusItem: NSStatusItem?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        menu.addItem(withTitle: "Tikatype", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Convert Selection",
                     action: #selector(convertSelectionAction),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",
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

    // MARK: - Actions

    @objc private func convertSelectionAction() {
        guard let other = otherLayout() else { return }
        TextConverter.convertSelected(from: LayoutManager.currentLayout, to: other)
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        perAppManager.applicationDidActivate(app)
        buffer.clear()
    }

    // MARK: - Conversion

    private func convertWord() {
        guard let other = otherLayout() else { return }
        TextConverter.replaceWord(buffer: buffer, switchingTo: other)
    }

    private func convertPhrase() {
        guard let other = otherLayout() else { return }
        TextConverter.replacePhrase(buffer: buffer, switchingTo: other)
    }

    private func otherLayout() -> TISInputSource? {
        let currentID = LayoutManager.sourceID(of: LayoutManager.currentLayout)
        return LayoutManager.availableLayouts.first { LayoutManager.sourceID(of: $0) != currentID }
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
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Tikatype needs Accessibility permission to monitor keyboard input. Please grant it in System Settings → Privacy & Security → Accessibility, then relaunch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}
