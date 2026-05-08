import Foundation

/// Persists user preferences via UserDefaults.
final class SettingsManager {

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case autoCorrect        = "autoCorrect"
        case realtimeCorrection = "realtimeCorrection"
        case hotkey             = "hotkey"
        case excludedApps       = "excludedApps"
        case launchAtLogin      = "launchAtLogin"
    }

    // MARK: - Properties

    var autoCorrect: Bool {
        get { defaults.object(forKey: Key.autoCorrect.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoCorrect.rawValue) }
    }

    /// Trigger real-time (per-character) layout correction in addition to post-word correction.
    var realtimeCorrection: Bool {
        get { defaults.object(forKey: Key.realtimeCorrection.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.realtimeCorrection.rawValue) }
    }

    /// Bundle IDs of apps where autocorrection is disabled.
    var excludedApps: Set<String> {
        get {
            let arr = defaults.stringArray(forKey: Key.excludedApps.rawValue) ?? []
            return Set(arr)
        }
        set { defaults.set(Array(newValue), forKey: Key.excludedApps.rawValue) }
    }

    var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }
}
