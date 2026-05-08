import Foundation

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

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
