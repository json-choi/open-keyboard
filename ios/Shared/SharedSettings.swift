import Foundation
import KeyboardCore

struct KeyboardSettings: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var layout = "dubeolsik"
    var typingLanguage = LanguageSupport.typingLanguage(preferred: Locale.preferredLanguages)
    var keyHeight: Double = 44
    /// Off by default: key feedback is opt-in.
    var haptics = false
    var sound = false
    /// Local-only text replacement and saved phrases.
    var shortcuts: [TextShortcut] = []
    var snippets: [String] = []
    /// Off by default. When on, copied text is kept only in keyboard memory while it runs.
    var clipboardHistory = false
    static let layouts = ["dubeolsik", "cheonjiin", "moaki"]
    static let keyHeights = 38.0...54.0
}

extension KeyboardSettings {
    /// Fields added later default when absent so an update never resets stored settings.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        layout = try values.decodeIfPresent(String.self, forKey: .layout).flatMap { Self.layouts.contains($0) ? $0 : nil } ?? layout
        typingLanguage = try values.decodeIfPresent(String.self, forKey: .typingLanguage).flatMap { ["ko", "en"].contains($0) ? $0 : nil } ?? typingLanguage
        keyHeight = min(Self.keyHeights.upperBound, max(Self.keyHeights.lowerBound, try values.decodeIfPresent(Double.self, forKey: .keyHeight) ?? keyHeight))
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? false
        sound = try values.decodeIfPresent(Bool.self, forKey: .sound) ?? false
        shortcuts = try values.decodeIfPresent([TextShortcut].self, forKey: .shortcuts) ?? []
        snippets = try values.decodeIfPresent([String].self, forKey: .snippets) ?? []
        clipboardHistory = try values.decodeIfPresent(Bool.self, forKey: .clipboardHistory) ?? false
    }
}

private func sharedFile(_ name: String) -> URL? {
    let group = AppInfo.appGroup
    guard !group.isEmpty else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent(name)
}

/// The extension records that it ran with Full Access, so the app can show the setup as done.
/// Without Full Access the extension cannot write to the App Group, which is itself the signal.
final class KeyboardActivationStore {
    private struct Observation: Codable { let observedAt: Date }
    private let url = sharedFile("keyboard-activation-v1.json")
    func record(fullAccess: Bool) {
        guard fullAccess, let url, let data = try? JSONEncoder().encode(Observation(observedAt: Date())) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    var previouslyActivatedWithFullAccess: Bool {
        guard let url, let data = try? Data(contentsOf: url), (try? JSONDecoder().decode(Observation.self, from: data)) != nil else { return false }
        return true
    }
}

/// Reading the App Group works without Full Access. Write only from the app,
/// or from the keyboard when it has Full Access.
final class SharedSettingsStore {
    enum StoreError: Error { case unavailable }
    private let fileURL = sharedFile("settings-v1.json")
    func read() -> KeyboardSettings {
        guard let url = fileURL, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(KeyboardSettings.self, from: data), value.schemaVersion == 1 else { return KeyboardSettings() }
        return value
    }
    func write(_ settings: KeyboardSettings, permitted: Bool = true) throws {
        guard permitted, let url = fileURL else { throw StoreError.unavailable }
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
