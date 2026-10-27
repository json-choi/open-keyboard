import Foundation
import KeyboardCore

/// Korean source strings are the keys; English comes from en.lproj. Any other device language gets English.
enum L10n {
    static var language: String { LanguageSupport.interfaceLanguage(preferred: Locale.preferredLanguages) }
    private static let english: Bundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    static func text(_ key: String, _ arguments: [Any] = []) -> String {
        let template = language == "ko" ? key : english.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return template }
        return LocalizedTemplate.render(template, arguments: arguments.map { String(describing: $0) })
    }
}

func L(_ key: String, _ arguments: Any...) -> String { L10n.text(key, arguments) }
