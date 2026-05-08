import Foundation

final class SettingsManager {

    private let defaults = UserDefaults.standard

    var excludedApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedApps") ?? []) }
        set { defaults.set(Array(newValue), forKey: "excludedApps") }
    }
}
