import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private let settings       = SettingsManager()
    private let buffer         = WordBuffer()
    private let detector       = LayoutDetector()
    private let perAppManager  = PerAppLayoutManager()
    private var corrector: AutoCorrector!
    private var monitor: KeyboardMonitor!

    // MARK: - Status bar

    private var statusItem: NSStatusItem?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        setupComponents()
        setupTriggers()
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
        corrector = AutoCorrector(detector: detector, buffer: buffer, settings: settings)
        monitor   = KeyboardMonitor(buffer: buffer, corrector: corrector, settings: settings)
    }

    private func setupTriggers() {
        let layouts = LayoutManager.availableLayouts
        guard let russian = layouts.first(where: { LayoutManager.isCyrillic($0) }),
              let latin   = layouts.first(where: { LayoutManager.isLatin($0) }) else {
            print("Tikatype: couldn't find Russian+Latin layouts — trigger list will be empty")
            return
        }
        detector.buildTriggers(
            russianWords: russianFrequencyWords(),
            russianLayout: russian,
            latinLayout: latin
        )
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "⌨"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Tikatype", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Auto-correct", action: #selector(toggleAutoCorrect), keyEquivalent: "")
        toggleItem.state = settings.autoCorrect ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func toggleAutoCorrect() {
        settings.autoCorrect = !settings.autoCorrect
        corrector.isEnabled  = settings.autoCorrect
        // Update menu checkmark
        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleAutoCorrect) {
                item.state = settings.autoCorrect ? .on : .off
            }
        }
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        perAppManager.applicationDidActivate(app)
        buffer.clear()   // Don't carry over a half-typed word across app switches
    }

    // MARK: - Accessibility check

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
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

// MARK: - Frequency word list

/// A minimal Russian frequency word list for trigger generation.
/// Replace with a fuller list (or load from a bundled file) for better accuracy.
private func russianFrequencyWords() -> [String] {
    return [
        "это", "как", "он", "она", "они", "мы", "вы", "я",
        "что", "не", "на", "в", "и", "а", "но", "или",
        "да", "нет", "так", "уже", "ещё", "всё", "все",
        "был", "была", "были", "есть", "будет", "будут",
        "здесь", "там", "когда", "где", "если", "чтобы",
        "только", "очень", "хорошо", "плохо", "можно",
        "нельзя", "нужно", "должен", "должна", "могут",
        "привет", "пока", "спасибо", "пожалуйста",
        "который", "которая", "которые", "которого",
        "время", "день", "год", "человек", "люди",
        "работа", "дом", "слово", "жизнь", "рука",
        "знаю", "знает", "знаешь", "думаю", "думает",
        "хочу", "хочет", "хотим", "хотите", "хотят",
        "иду", "идёт", "идём", "идёте", "идут",
        "вижу", "видит", "видим", "видите", "видят",
        "говорю", "говорит", "говорим", "говорят",
        "сказал", "сказала", "сказали", "сказали",
        "было", "стало", "стали", "стал", "стала",
    ]
}
