import Foundation

/// Name and App Group come from Config/Product.xcconfig through Info.plist, so a rename touches one file.
enum AppInfo {
    private static func value(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
    static var name: String { L10n.language == "ko" ? value("ProductDisplayNameKo") : value("CFBundleDisplayName") }
    static var appGroup: String { value("SharedAppGroup") }
}
