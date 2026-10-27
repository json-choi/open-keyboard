import Foundation

/// Local, release-to-commit strokes. Coordinates use screen axes (positive y down).
/// Each accepted sample advances the anchor; repeated directions form a single stroke.
public struct MoakiGesture {
    private let threshold: Double
    private var x = 0.0, y = 0.0
    private var path = ""
    private var invalidTurn = false
    private var unrecognizedDistance = 0.0
    public init(threshold: Double = 12) { self.threshold = max(1, threshold) }
    public static func activationDistance(keyWidth: Double, keyHeight: Double) -> Double {
        guard keyWidth.isFinite, keyHeight.isFinite, keyWidth > 0, keyHeight > 0 else { return 12 }
        return min(16, max(8, min(keyWidth, keyHeight) * 0.24))
    }
    public mutating func move(x: Double, y: Double) {
        let dx = x - self.x, dy = y - self.y
        guard dx * dx + dy * dy >= threshold * threshold else { return }
        let direction: Character
        if abs(dy) < abs(dx) * 0.41421356237 { direction = dx > 0 ? "R" : "L" }
        else if abs(dx) < abs(dy) * 0.41421356237 { direction = dy > 0 ? "D" : "U" }
        else { direction = dy > 0 ? "E" : "I" }
        self.x = x; self.y = y
        if path.last != direction {
            let candidate = path + String(direction)
            // A rounded corner can momentarily look diagonal. Keep the last
            // valid prefix so the following cardinal stroke can recover it.
            if Self.vowels.keys.contains(where: { $0.hasPrefix(candidate) }) {
                path = candidate; invalidTurn = false; unrecognizedDistance = 0
            } else {
                unrecognizedDistance += hypot(dx, dy)
                if unrecognizedDistance >= threshold * 1.5 { invalidTurn = true }
            }
        } else { unrecognizedDistance = 0 }
    }
    public var hasStroke: Bool { !path.isEmpty }
    public var vowel: Character? { invalidTurn ? nil : Self.vowels[path] }
    /// Empty base is the dedicated vowel key. Invalid strokes insert nothing.
    public func input(base: String) -> String? {
        guard hasStroke else { return base.isEmpty ? "ㅣ" : base }
        guard let vowel else { return nil }
        return base + String(vowel)
    }
    private static let vowels: [String: Character] = [
        "R": "ㅏ", "RL": "ㅐ", "RLR": "ㅑ", "RLRL": "ㅒ",
        "L": "ㅓ", "LR": "ㅔ", "LRL": "ㅕ", "LRLR": "ㅖ",
        "U": "ㅗ", "UR": "ㅘ", "URL": "ㅙ", "UD": "ㅚ", "UDU": "ㅛ",
        "D": "ㅜ", "DL": "ㅝ", "DLR": "ㅞ", "DU": "ㅟ", "DUD": "ㅠ",
        "E": "ㅡ", "EI": "ㅢ", "EU": "ㅢ", "I": "ㅣ"
    ]
}

/// Familiar Moaki grid, with narrow punctuation columns and number holds.
public enum MoakiLayout {
    public static let rows = [["~", "ㅃ", "ㅉ", "ㄸ", "ㄲ", "ㅆ", "!"],
        ["^", "ㅂ", "ㅈ", "ㄷ", "ㄱ", "ㅅ", "?"],
        [";", "ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "."],
        ["*", "ㅋ", "ㅌ", "ㅊ", "ㅍ", "⌫"]]
    public static let consonants = Set("ㅃㅉㄸㄲㅆㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎㅋㅌㅊㅍ".map(String.init))
    public static let numbers = Dictionary(uniqueKeysWithValues: zip("ㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎ".map(String.init), "1234567890".map(String.init)))
    public static func weights(row: Int) -> [Double] {
        row == 3 ? [0.6, 1, 1, 1, 1, 1.6] : [0.6, 1, 1, 1, 1, 1, 0.6]
    }
}
