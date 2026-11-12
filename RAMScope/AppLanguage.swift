import Foundation

/// Interface language chosen in the app. Switching takes effect immediately, without relaunching:
/// strings are looked up in the chosen `.lproj` directly instead of through the system language order.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "appLanguage"

    var id: Self { self }

    /// The `.lproj` used for lookups. `.system` lets macOS pick among the localizations the app ships,
    /// falling back to the development region (English) for unsupported system languages.
    private var localization: String {
        switch self {
        case .system: Bundle.main.preferredLocalizations.first ?? Self.english.rawValue
        case .english, .simplifiedChinese: rawValue
        }
    }

    var locale: Locale { Locale(identifier: localization) }

    private var bundle: Bundle {
        Bundle.main.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }

    /// Languages are listed in their own names so they stay recognizable whatever language is active.
    func title(in active: AppLanguage) -> String {
        switch self {
        case .system: active.localized("System")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}
