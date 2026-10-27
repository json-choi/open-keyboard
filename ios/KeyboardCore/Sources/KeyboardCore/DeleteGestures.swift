import Foundation

/// Held-delete pacing: one character per repeat, two after 20 repeats (HeliBoard's DELETE_ACCELERATE_AT),
/// then a word per repeat once the key has been held for 3 seconds (KeyboardKit's backspace range).
public enum DeleteRepeat {
    public enum Step: Equatable, Sendable { case characters(Int), word }
    public static let accelerateAfter = 20
    public static let wordAfter: TimeInterval = 3
    public static func step(repeats: Int, held: TimeInterval) -> Step {
        held > wordAfter ? .word : repeats > accelerateAfter ? .characters(2) : .characters(1)
    }
    /// Trailing whitespace plus the last word of `before`; punctuation ends a word once letters were found.
    public static func lastWord(in before: String) -> String {
        var text = Substring(before), removed = 0
        while let last = text.last, last.isWhitespace { text.removeLast(); removed += 1 }
        var letters = false
        while let last = text.last {
            let delimiter = last.isWhitespace || last.isPunctuation || last.isSymbol
            if delimiter && letters { break }
            letters = !delimiter || letters
            text.removeLast(); removed += 1
        }
        return String(before.suffix(removed))
    }
}

/// Sliding left from delete removes one character per step and sliding back restores them, like
/// HeliBoard's delete slider. iOS keyboards cannot select host text, so the removal is live and undoable.
public struct DeleteSlide: Sendable {
    /// Points per character, HeliBoard's 10dp pointer step.
    public static let step = 10.0
    /// The text before the cursor when the slide began. The host reflects edits late, so later reads
    /// are not trusted for what the slide removed.
    private let origin: [Character]
    public private(set) var removed = 0
    public init(before: String?) { origin = Array(before ?? "") }
    public static func count(dx: Double) -> Int { dx < 0 ? Int(-dx / step) : 0 }
    /// Brings the removal to `target` characters. Returns how many to delete, or the text to restore.
    public mutating func move(to target: Int) -> (delete: Int, restore: String) {
        let goal = min(max(0, target), origin.count)
        defer { removed = goal }
        if goal > removed { return (goal - removed, "") }
        return (0, String(origin[(origin.count - removed)..<(origin.count - goal)]))
    }
}
