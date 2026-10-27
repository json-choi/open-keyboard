import Foundation

/// Pure two-set Hangul composition, independent of the host text input API.
public struct HangulComposer: Sendable {
    private var inputs: [Character] = []
    public init() {}
    public var text: String { Self.compose(inputs) }
    public var isEmpty: Bool { inputs.isEmpty }
    public mutating func append(_ value: Character) { inputs.append(value) }
    public mutating func replaceLast(_ value: Character) { if !inputs.isEmpty { inputs.removeLast() }; inputs.append(value) }
    @discardableResult public mutating func delete() -> Bool {
        guard !inputs.isEmpty else { return false }; inputs.removeLast(); return true
    }
    public mutating func reset() { inputs.removeAll(keepingCapacity: false) }

    static let leads = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let tails: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map(Optional.some)
    static let vowelPairs: [String: Character] = ["ㅗㅏ":"ㅘ","ㅗㅐ":"ㅙ","ㅗㅣ":"ㅚ","ㅘㅣ":"ㅙ","ㅜㅓ":"ㅝ","ㅜㅔ":"ㅞ","ㅜㅣ":"ㅟ","ㅝㅣ":"ㅞ","ㅡㅣ":"ㅢ"]
    static let tailPairs: [String: Character] = ["ㄱㅅ":"ㄳ","ㄴㅈ":"ㄵ","ㄴㅎ":"ㄶ","ㄹㄱ":"ㄺ","ㄹㅁ":"ㄻ","ㄹㅂ":"ㄼ","ㄹㅅ":"ㄽ","ㄹㅌ":"ㄾ","ㄹㅍ":"ㄿ","ㄹㅎ":"ㅀ","ㅂㅅ":"ㅄ"]
    static let splitTails: [Character: (Character, Character)] = ["ㄳ":("ㄱ","ㅅ"),"ㄵ":("ㄴ","ㅈ"),"ㄶ":("ㄴ","ㅎ"),"ㄺ":("ㄹ","ㄱ"),"ㄻ":("ㄹ","ㅁ"),"ㄼ":("ㄹ","ㅂ"),"ㄽ":("ㄹ","ㅅ"),"ㄾ":("ㄹ","ㅌ"),"ㄿ":("ㄹ","ㅍ"),"ㅀ":("ㄹ","ㅎ"),"ㅄ":("ㅂ","ㅅ")]

    private static func compose(_ inputs: [Character]) -> String {
        var committed = "", lead: Character?, vowel: Character?, tail: Character?
        func current() -> String {
            if let l = lead, let v = vowel, let li = leads.firstIndex(of: l), let vi = vowels.firstIndex(of: v) {
                let ti = tails.firstIndex(where: { $0 == tail }) ?? 0
                return String(UnicodeScalar(0xAC00 + (li * 21 + vi) * 28 + ti)!)
            }
            return [lead, vowel].compactMap { $0 }.map(String.init).joined()
        }
        func flush() { committed += current(); lead = nil; vowel = nil; tail = nil }
        for char in inputs {
            if vowels.contains(char) {
                if vowel == nil { vowel = char }
                else if let t = tail {
                    let moved: Character
                    if let pair = splitTails[t] { tail = pair.0; moved = pair.1 }
                    else { tail = nil; moved = t }
                    committed += current(); lead = moved; vowel = char; tail = nil
                } else if let combined = vowelPairs[String(vowel!) + String(char)] { vowel = combined }
                else { flush(); vowel = char }
            } else if leads.contains(char) {
                if lead == nil && vowel == nil { lead = char }
                else if lead != nil && vowel != nil && tail == nil && tails.contains(where: { $0 == char }) { tail = char }
                else if let t = tail, let combined = tailPairs[String(t) + String(char)] { tail = combined }
                else { flush(); lead = char }
            } else { flush(); committed.append(char) }
        }
        return committed + current()
    }
}

/// Cheonjiin's three vowel primitives and timed consonant cycling share the same
/// Hangul composer. Cycling is explicit so time comes from the platform adapter.
public struct CheonjiinComposer: Sendable {
    private var tokens: [Character] = []
    private var vowelSequence = ""
    private var hasVowelToken = false
    public init() {}
    public var text: String {
        var composer = HangulComposer(); for token in tokens { composer.append(token) }; return composer.text
    }
    public var isEmpty: Bool { tokens.isEmpty }
    private static let vowelMap: [String: Character] = [
        "ㅣ":"ㅣ", "ㅡ":"ㅡ", "ㆍ":"ㆍ", "ㆍㆍ":"ᆢ",
        "ㅣㆍ":"ㅏ", "ㅣㆍㆍ":"ㅑ", "ㆍㅣ":"ㅓ", "ㆍㆍㅣ":"ㅕ",
        "ㆍㅡ":"ㅗ", "ㆍㆍㅡ":"ㅛ", "ㅡㆍ":"ㅜ", "ㅡㆍㆍ":"ㅠ", "ㅡㅣ":"ㅢ",
        "ㅣㆍㅣ":"ㅐ", "ㅣㆍㆍㅣ":"ㅒ", "ㆍㅣㅣ":"ㅔ", "ㆍㆍㅣㅣ":"ㅖ",
        "ㆍㅡㅣ":"ㅚ", "ㆍㅡㅣㆍ":"ㅘ", "ㆍㅡㅣㆍㅣ":"ㅙ",
        "ㅡㆍㅣ":"ㅟ", "ㅡㆍㆍㅣ":"ㅝ", "ㅡㆍㆍㅣㅣ":"ㅞ"
    ]
    public mutating func primitive(_ key: Character) {
        let candidate = vowelSequence + String(key)
        if let vowel = Self.vowelMap[candidate] {
            if hasVowelToken { tokens.removeLast() }; tokens.append(vowel)
            vowelSequence = candidate; hasVowelToken = true
        } else {
            vowelSequence = String(key); tokens.append(key); hasVowelToken = true
        }
    }
    public mutating func consonant(_ char: Character, replacePrevious: Bool) {
        vowelSequence = ""; hasVowelToken = false
        if replacePrevious && !tokens.isEmpty { tokens.removeLast() }
        tokens.append(char)
    }
    @discardableResult public mutating func delete() -> Bool {
        guard !tokens.isEmpty else { return false }
        if hasVowelToken && vowelSequence.count > 1 {
            vowelSequence.removeLast(); tokens.removeLast()
            if let char = Self.vowelMap[vowelSequence] { tokens.append(char) }
        } else { tokens.removeLast(); vowelSequence = ""; hasVowelToken = false }
        return true
    }
    public mutating func endCycle() { vowelSequence = ""; hasVowelToken = false }
    public mutating func reset() { tokens.removeAll(); vowelSequence = ""; hasVowelToken = false }
}
