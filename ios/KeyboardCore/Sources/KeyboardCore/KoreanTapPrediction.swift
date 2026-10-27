import Foundation

/// Next-key likelihood for dubeolsik taps, after KeyboardKit's dynamic tap areas and Gunawardana et al.'s
/// anchored key-target resizing. The Hangul automaton (onset, open or closed vowel, open or closed final)
/// decides which keys can come next: a compound continuation (ㅗ→ㅏㅐㅣ, ㄹ→ㄱㅁㅂㅅㅌㅍㅎ), another
/// consonant or another vowel. `KoreanTapModel` says how often each happened; keys of one class share it.
public struct KoreanTapPrediction: Sendable {
    /// The 33 dubeolsik key values, shifted keys included.
    public static let keys: Set<Character> = Set("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅛㅜㅠㅡㅣ")
    /// Reach given up per unit of log-probability: the boundary shift between two Gaussian key models,
    /// w·σx² with σx ≈ 0.32 key widths and language weight w ≈ 0.6 (Adhikary 2023; Gunawardana 2010).
    public static let steepness = 0.06
    private enum State: Int { case start, onset, openVowel, vowel, openFinal, final }
    private enum Kind: Int { case pair, consonant, vowel }
    private static let consonants = 19, vowels = 14
    /// Vowels that combine with a next vowel, and finals that take a second consonant.
    private static let pairs: [Character: String] = ["ㅗ": "ㅏㅐㅣ", "ㅜ": "ㅓㅔㅣ", "ㅡ": "ㅣ", "ㄱ": "ㅅ", "ㄴ": "ㅈㅎ", "ㄹ": "ㄱㅁㅂㅅㅌㅍㅎ", "ㅂ": "ㅅ"]
    private static let neverFinal: Set<Character> = Set("ㄸㅃㅉ")
    private var state = State.start
    private var last: Character = " "
    public init() {}
    /// Records a pressed key. Anything but a dubeolsik jamo key (space, symbol, delete) starts over.
    public mutating func record(_ value: String) {
        guard value.count == 1, let key = value.first, Self.keys.contains(key) else { reset(); return }
        state = Self.advance(state, last, key); last = key
    }
    public mutating func reset() { state = .start; last = " " }
    /// Probability that the next tap is `value`, or nil at a word start, where any key is plausible.
    public func probability(of value: String) -> Double? {
        guard value.count == 1, let key = value.first, Self.keys.contains(key), let each = perKey() else { return nil }
        return each[Self.kind(state, last, key).rawValue]
    }
    /// How far `value` reaches into its neighbours (see `KeyboardTouchTarget.resolve`): the likeliest keys
    /// reach `KeyboardTouchTarget.maxReach`, and each halving of probability gives up `steepness`·ln 2.
    public func reach(of value: String) -> Double? {
        guard let chance = probability(of: value), let best = perKey()?.max() else { return nil }
        return max(0, KeyboardTouchTarget.maxReach + Self.steepness * log(chance / best))
    }
    /// Each class's probability per key, or nil without context.
    private func perKey() -> [Double]? {
        guard state != .start else { return nil }
        let pairs = state == .openVowel || state == .openFinal ? Self.pairs[last]?.count ?? 0 : 0
        let sizes = [pairs, Self.consonants - (state == .openFinal ? pairs : 0), Self.vowels - (state == .openVowel ? pairs : 0)]
        // Add-one smoothing over the classes that exist here, so no key is ever impossible.
        let counts = sizes.indices.map { sizes[$0] > 0 ? Double(KoreanTapModel.classCounts[state.rawValue * 3 + $0] + 1) : 0 }
        let total = counts.reduce(0, +)
        return sizes.indices.map { sizes[$0] > 0 ? counts[$0] / total / Double(sizes[$0]) : 0 }
    }
    private static func vowel(_ key: Character) -> Bool { key >= "ㅏ" }
    private static func advance(_ state: State, _ last: Character, _ key: Character) -> State {
        if vowel(key) {
            if state == .openVowel, pairs[last]?.contains(key) == true { return .vowel }
            return pairs[key] != nil ? .openVowel : .vowel
        }
        if state == .openVowel || state == .vowel, !neverFinal.contains(key) { return pairs[key] != nil ? .openFinal : .final }
        if state == .openFinal, pairs[last]?.contains(key) == true { return .final }
        return .onset
    }
    private static func kind(_ state: State, _ last: Character, _ key: Character) -> Kind {
        if state == .openVowel || state == .openFinal, pairs[last]?.contains(key) == true { return .pair }
        return vowel(key) ? .vowel : .consonant
    }
}
