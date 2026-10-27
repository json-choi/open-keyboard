import Foundation

/// Interface strings ship in Korean and English; anything else falls back to English.
public enum LanguageSupport {
    public static let languages = ["ko", "en"]
    public static func canonical(_ tag: String) -> String? {
        let locale = Locale(identifier: tag.replacingOccurrences(of: "_", with: "-"))
        guard let language = locale.language.languageCode?.identifier, languages.contains(language) else { return nil }
        return language
    }
    public static func interfaceLanguage(preferred: [String]) -> String {
        preferred.compactMap(canonical).first ?? "en"
    }
    public static func typingLanguage(preferred: [String]) -> String { interfaceLanguage(preferred: preferred) == "ko" ? "ko" : "en" }
}

public enum LocalizedTemplate {
    private static let placeholder = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
    /// Substitute only placeholders in the template, never braces in a user's text.
    public static func render(_ template: String, arguments: [String]) -> String {
        guard !arguments.isEmpty, template.contains("{") else { return template }
        let source = template as NSString
        let result = NSMutableString(string: template)
        for match in placeholder.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            if let index = Int(source.substring(with: match.range(at: 1))), arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: arguments[index])
            }
        }
        return result as String
    }
}
