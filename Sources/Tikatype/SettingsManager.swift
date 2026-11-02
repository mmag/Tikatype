import Foundation
import ServiceManagement

final class SettingsManager {

    private let defaults = UserDefaults.standard

    var primaryLayoutID: String? {
        get { defaults.string(forKey: "primaryLayoutID") }
        set { defaults.set(newValue, forKey: "primaryLayoutID") }
    }

    var secondaryLayoutID: String? {
        get { defaults.string(forKey: "secondaryLayoutID") }
        set { defaults.set(newValue, forKey: "secondaryLayoutID") }
    }

    var excludedApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedApps") ?? []) }
        set { defaults.set(Array(newValue), forKey: "excludedApps") }
    }

    /// Launch-at-login is backed by the system login item (SMAppService), not
    /// just a stored flag. The UserDefaults key mirrors the user's intent so the
    /// registration can be re-applied on launch if the system lost it.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Tikatype: launch-at-login %@ failed: %@",
                      newValue ? "register" : "unregister", "\(error)")
            }
        }
    }

    /// Re-applies the stored launch-at-login intent to the system login item.
    /// Call once at startup: earlier versions only stored the flag and never
    /// registered anything, and the registration can also be lost after the
    /// app bundle is replaced (e.g. a cask upgrade).
    func syncLaunchAtLogin() {
        guard defaults.bool(forKey: "launchAtLogin") else { return }
        let status = SMAppService.mainApp.status
        guard status != .enabled, status != .requiresApproval else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Tikatype: launch-at-login re-register failed: %@", "\(error)")
        }
    }
}
