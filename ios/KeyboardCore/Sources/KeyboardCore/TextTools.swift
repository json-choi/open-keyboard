import Foundation

public struct TextShortcut: Codable, Equatable, Sendable {
    public var trigger: String
    public var expansion: String
    public init(trigger: String, expansion: String) { self.trigger = trigger; self.expansion = expansion }
}

/// Local text replacement. Matching reads only the word before the cursor.
public enum TextShortcuts {
    public static let maxCount = 300
    public static let maxTrigger = 20
    public static let maxExpansion = 500
    public static func validate(trigger: String, expansion: String, existing: [TextShortcut], replacing: String? = nil) -> String? {
        if trigger.isEmpty || trigger.contains(where: { $0.isWhitespace }) { return "단축어는 공백 없이 입력해 주세요" }
        if trigger.count > maxTrigger { return "단축어는 20자까지 입력할 수 있어요" }
        if expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expansion.count > maxExpansion { return "바꿀 문구는 1~500자로 입력해 주세요" }
        if trigger == expansion { return "단축어와 문구가 같아요" }
        if existing.contains(where: { $0.trigger == trigger && $0.trigger != replacing }) { return "이미 등록한 단축어예요" }
        if replacing == nil && existing.count >= maxCount { return "단축어는 300개까지 등록할 수 있어요" }
        return nil
    }
    /// The trigger must be the whole last word: "ㅂㄱ" matches "안녕 ㅂㄱ" but not "ㅂㅂㄱ".
    public static func match(before: String?, shortcuts: [TextShortcut]) -> TextShortcut? {
        guard let before, let last = before.last, !last.isWhitespace else { return nil }
        let word = before.lastIndex(where: { $0.isWhitespace }).map { String(before[before.index(after: $0)...]) } ?? before
        return shortcuts.first { $0.trigger == word }
    }
}

/// Saved phrases the user inserts with one tap.
public enum Snippets {
    public static let maxCount = 50
    public static let maxLength = 500
    public static func validate(_ value: String, existing: [String], replacing: String? = nil) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.count > maxLength { return "문구는 1~500자로 입력해 주세요" }
        if existing.contains(where: { $0 == value && $0 != replacing }) { return "이미 등록한 문구예요" }
        if replacing == nil && existing.count >= maxCount { return "문구는 50개까지 등록할 수 있어요" }
        return nil
    }
}

/// Memory-only recent clipboard list. It is never written to storage.
public struct ClipboardHistory: Sendable {
    public private(set) var items: [String] = []
    private let capacity: Int
    private let maxLength: Int
    public init(capacity: Int = 10, maxLength: Int = 2000) { self.capacity = capacity; self.maxLength = maxLength }
    public mutating func add(_ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= maxLength else { return }
        items.removeAll { $0 == value }; items.insert(value, at: 0)
        if items.count > capacity { items.removeLast(items.count - capacity) }
    }
    public mutating func clear() { items.removeAll() }
}
