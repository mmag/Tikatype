import Foundation

enum L10n {

    private static let ru: Bool =
        Locale.preferredLanguages.first?.hasPrefix("ru") ?? false

    private static func s(_ en: String, _ ru: String) -> String { L10n.ru ? ru : en }

    // MARK: - Menu
    static var menuAbout:            String { s("About Tikatype",          "О программе") }
    static var menuSettings:         String { s("Settings…",               "Настройки…") }
    static var menuConvertSelection: String { s("Convert Selection",       "Конвертировать выделенное") }
    static var menuQuit:             String { s("Quit",                    "Выйти") }

    // MARK: - About
    static var aboutVersion:         String { s("Version",                 "Версия") }
    static var aboutOK:              String { s("OK",                      "ОК") }
    static var aboutDescription:     String { s(
        "Converts text between keyboard layouts.\n\nCtrl+Shift — convert last word\nDouble Opt — convert phrase",
        "Конвертирует текст между раскладками клавиатуры.\n\nCtrl+Shift — последнее слово\nДвойной Opt — фраза от последнего знака препинания"
    )}

    // MARK: - Settings window
    static var settingsTitle:         String { s("Settings",               "Настройки") }
    static var settingsLayouts:       String { s("LAYOUTS",                "РАСКЛАДКИ") }
    static var settingsPrimary:       String { s("Primary:",               "Основная:") }
    static var settingsSecondary:     String { s("Secondary:",             "Вспомогательная:") }
    static var settingsHotkeys:       String { s("HOTKEYS",               "ГОРЯЧИЕ КЛАВИШИ") }
    static var settingsWord:          String { s("Last word:",             "Последнее слово:") }
    static var settingsPhrase:        String { s("Phrase:",                "Фраза:") }
    static var settingsSelection:     String { s("Selection:",             "Выделенное:") }
    static var settingsMenuOnly:      String { s("Menu item",              "Пункт меню") }
    static var settingsExcluded:      String { s("EXCLUDED APPS",          "ИСКЛЮЧЁННЫЕ ПРИЛОЖЕНИЯ") }
    static var settingsLaunchLogin:   String { s("Launch at login",        "Запускать при входе") }
    static var settingsAdd:           String { s("+",                      "+") }
    static var settingsRemove:        String { s("−",                      "−") }
}
