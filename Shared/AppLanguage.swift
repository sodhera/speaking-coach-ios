import Foundation

/// The one language the whole app speaks: every screen, the voice partner,
/// the feedback and the notifications. Chosen on the first screen, changed
/// in Settings. Stored in the App Group so the Screen Time extensions, which
/// run in their own processes, speak it too.
enum AppLanguage {
    /// Practice codes, as the voice partner and the server know them.
    static let supported = [
        "en", "es", "fr", "de", "it", "pt", "nl", "pl", "sv", "tr",
        "ru", "uk", "hi", "ar", "ja", "ko", "zh", "id", "tl", "vi",
    ]

    private static let key = "app.language"
    private static var store: UserDefaults { UserDefaults(suiteName: RoutineShared.appGroup) ?? .standard }

    /// Nil until the user has chosen. Nothing defaults to English.
    static var chosen: String? {
        store.string(forKey: key).flatMap { supported.contains($0) ? $0 : nil }
    }

    /// The chosen language, or the phone's own while nothing is chosen yet.
    static var code: String { chosen ?? deviceLanguage }

    /// The phone's language when the app supports it; English otherwise.
    static var deviceLanguage: String {
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? ""
            let practice = code == "fil" ? "tl" : code
            if supported.contains(practice) { return practice }
        }
        return "en"
    }

    static func choose(_ code: String) {
        guard supported.contains(code) else { return }
        store.set(code, forKey: key)
        // The system reads this at launch, so its own sheets (permissions,
        // pickers) and the next launch start in this language too.
        UserDefaults.standard.set([localization(for: code)], forKey: "AppleLanguages")
        cachedBundle = nil
    }

    #if DEBUG
    /// Back to first run, for review and UI-test launches.
    static func forget() {
        store.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        cachedBundle = nil
    }
    #endif

    /// The `.lproj` folder the strings for a practice code live in.
    static func localization(for code: String) -> String {
        switch code {
        case "zh": "zh-Hans"
        case "tl": "fil"
        case "pt": "pt-BR"
        default: code
        }
    }

    static var locale: Locale { Locale(identifier: localization(for: code)) }
    static var isRightToLeft: Bool { code == "ar" }

    /// A string in a language that isn't (yet) the app's own: the picker
    /// speaks each language as it's tapped, before anything is chosen.
    static func string(_ key: String, in code: String) -> String {
        guard let path = Bundle.main.path(forResource: localization(for: code), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// The language's name in itself: "Deutsch", "Español", "日本語".
    static func autonym(_ code: String) -> String {
        let id = localization(for: code)
        let name = Locale(identifier: id).localizedString(forIdentifier: id.components(separatedBy: "-")[0]) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The language's name in the app's current language: "German".
    static func name(_ code: String) -> String {
        let name = locale.localizedString(forLanguageCode: localization(for: code).components(separatedBy: "-")[0]) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    nonisolated(unsafe) private static var cachedBundle: Bundle?

    /// The strings bundle for the current language.
    static var bundle: Bundle {
        if let cachedBundle { return cachedBundle }
        let path = Bundle.main.path(forResource: localization(for: code), ofType: "lproj")
            ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
        cachedBundle = bundle
        return bundle
    }

    /// Routes `Bundle.main` lookups through the chosen language, so a choice
    /// takes effect at once rather than on relaunch. `String(localized:)`
    /// resolves its language once per process, so the app passes `bundle`
    /// to it explicitly; SwiftUI's `Text` follows the environment's locale.
    static func install() {
        guard !(Bundle.main is LanguageBundle) else { return }
        object_setClass(Bundle.main, LanguageBundle.self)
    }
}

private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let bundle = AppLanguage.bundle
        guard bundle !== self else { return super.localizedString(forKey: key, value: value, table: tableName) }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
