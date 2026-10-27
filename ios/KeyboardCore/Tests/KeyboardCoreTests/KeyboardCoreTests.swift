import XCTest
@testable import KeyboardCore

final class KeyboardCoreTests: XCTestCase {
    func testInterfaceAndTypingLanguages() {
        for (tag, expected) in ["en-GB": "en", "ko-KR": "ko", "ko_KR": "ko", "en": "en"] { XCTAssertEqual(LanguageSupport.canonical(tag), expected, tag) }
        XCTAssertNil(LanguageSupport.canonical("ja-JP"))
        XCTAssertEqual(LanguageSupport.interfaceLanguage(preferred: ["fr-FR"]), "en")
        XCTAssertEqual(LanguageSupport.interfaceLanguage(preferred: ["fr-FR", "ko-KR"]), "ko")
        XCTAssertEqual(LanguageSupport.typingLanguage(preferred: ["ko-KR"]), "ko")
        XCTAssertEqual(LanguageSupport.typingLanguage(preferred: ["ja-JP"]), "en")
    }
    func testLocalizedTemplateKeepsUserTextVerbatim() {
        XCTAssertEqual(LocalizedTemplate.render("原文: {0}\n提案: {1}", arguments: ["{1} $1\\ \"が\"", "中文"]), "原文: {1} $1\\ \"が\"\n提案: 中文")
        XCTAssertEqual(LocalizedTemplate.render("{0}", arguments: []), "{0}")
        XCTAssertEqual(LocalizedTemplate.render("{0} / {0}", arguments: ["中文"]), "中文 / 中文")
    }
    func composed(_ input: String) -> String { var composer = HangulComposer(); for char in input { composer.append(char) }; return composer.text }
    func testSyllablesAndFinalMigration() {
        let cases = ["ㅎㅏㄴㄱㅡㄹ":"한글", "ㄱㅏㄴㅏ":"가나", "ㄱㅏㄹㄱㅏ":"갈가", "ㅇㅣㄹㄱㅇㅓ":"읽어", "ㄷㅏㄹㄱ":"닭", "ㄱㅗㅏ":"과", "ㅅㅗㅣ":"쇠", "ㄱㅜㅓㄴ":"권", "ㄲㅏㄲ":"깎", "ㄱㅏㄱㅅㅏ":"각사", "ㄱㅏㅃㅏ":"가빠"]
        for (input, output) in cases { XCTAssertEqual(composed(input), output, input) }
    }
    func testEveryModernHangulSyllableFromKeyboardJamo() {
        let vowels: [Character: String] = ["ㅘ":"ㅗㅏ", "ㅙ":"ㅗㅐ", "ㅚ":"ㅗㅣ", "ㅝ":"ㅜㅓ", "ㅞ":"ㅜㅔ", "ㅟ":"ㅜㅣ", "ㅢ":"ㅡㅣ"]
        let tails: [Character: String] = ["ㄳ":"ㄱㅅ", "ㄵ":"ㄴㅈ", "ㄶ":"ㄴㅎ", "ㄺ":"ㄹㄱ", "ㄻ":"ㄹㅁ", "ㄼ":"ㄹㅂ", "ㄽ":"ㄹㅅ", "ㄾ":"ㄹㅌ", "ㄿ":"ㄹㅍ", "ㅀ":"ㄹㅎ", "ㅄ":"ㅂㅅ"]
        for (li, lead) in HangulComposer.leads.enumerated() {
            for (vi, vowel) in HangulComposer.vowels.enumerated() {
                for (ti, tail) in HangulComposer.tails.enumerated() {
                    let input = String(lead) + (vowels[vowel] ?? String(vowel)) + (tail.map { tails[$0] ?? String($0) } ?? "")
                    let expected = String(UnicodeScalar(0xAC00 + (li * 21 + vi) * 28 + ti)!)
                    XCTAssertEqual(composed(input), expected, input)
                }
            }
        }
    }
    func testConsecutiveDeletionRecomposesCompoundAndTail() {
        var composer = HangulComposer(); for char in "ㄱㅗㅏㄴ" { composer.append(char) }
        XCTAssertEqual(composer.text, "관"); XCTAssertTrue(composer.delete()); XCTAssertEqual(composer.text, "과")
        XCTAssertTrue(composer.delete()); XCTAssertEqual(composer.text, "고")
        XCTAssertTrue(composer.delete()); XCTAssertEqual(composer.text, "ㄱ")
        XCTAssertTrue(composer.delete()); XCTAssertEqual(composer.text, ""); XCTAssertFalse(composer.delete())
    }
    func testStandaloneJamoAndUnicode() {
        XCTAssertEqual(composed("ㄱㄱㅏ"), "ㄱ가")
        XCTAssertEqual(composed("ㅗㅏ"), "ㅘ")
        XCTAssertEqual(composed("ㅎㅏ😊"), "하😊")
    }
    func testCheonjiinVowelsAndCycles() {
        var composer = CheonjiinComposer()
        composer.consonant("ㄱ", replacePrevious: false); composer.primitive("ㅣ"); composer.primitive("ㆍ")
        XCTAssertEqual(composer.text, "가")
        composer.primitive("ㅣ"); XCTAssertEqual(composer.text, "개")
        XCTAssertTrue(composer.delete()); XCTAssertEqual(composer.text, "가")
        composer.consonant("ㄴ", replacePrevious: false); XCTAssertEqual(composer.text, "간")
        composer.consonant("ㄹ", replacePrevious: true); XCTAssertEqual(composer.text, "갈")
        composer.reset(); composer.consonant("ㄱ", replacePrevious: false)
        for char in "ㆍㅡㅣㆍ" { composer.primitive(char) }; XCTAssertEqual(composer.text, "과")
    }
    func testKeyFeedbackPlaysOncePerPressEvenWhenFastPressesOverlap() {
        var ledger = KeyFeedbackLedger()
        XCTAssertTrue(ledger.press(at: 10.00)); XCTAssertFalse(ledger.input(at: 10.04))
        // Two fingers overlap: both commits stay silent (the old single timestamp replayed B's haptic).
        XCTAssertTrue(ledger.press(at: 11.00)); XCTAssertTrue(ledger.press(at: 11.05))
        XCTAssertFalse(ledger.input(at: 11.08)); XCTAssertFalse(ledger.input(at: 11.12))
        // Touches of one event share a haptic but still own a silent commit each.
        XCTAssertTrue(ledger.press(at: 12.000)); XCTAssertFalse(ledger.press(at: 12.003))
        XCTAssertFalse(ledger.input(at: 12.05)); XCTAssertFalse(ledger.input(at: 12.06))
        // Held delete: the first deletion belongs to the press, repeats give their own feedback.
        XCTAssertTrue(ledger.press(at: 13.00)); XCTAssertFalse(ledger.input(at: 13.01))
        XCTAssertTrue(ledger.input(at: 13.50)); XCTAssertTrue(ledger.input(at: 13.60))
        // A press cancelled without input lapses after a pause instead of silencing later input.
        XCTAssertTrue(ledger.press(at: 20.00)); XCTAssertTrue(ledger.input(at: 22.00))
        ledger.reset(); XCTAssertTrue(ledger.input(at: 30.00))
    }
    func testShortcutMatchesOnlyTheWholeLastWord() {
        let shortcuts = [TextShortcut(trigger: "ㅂㄱ", expansion: "반갑습니다"), TextShortcut(trigger: "주소", expansion: "○○시 ○○구 ○○로 1")]
        XCTAssertEqual(TextShortcuts.match(before: "안녕하세요 ㅂㄱ", shortcuts: shortcuts)?.expansion, "반갑습니다")
        XCTAssertEqual(TextShortcuts.match(before: "ㅂㄱ", shortcuts: shortcuts)?.expansion, "반갑습니다")
        XCTAssertTrue(TextShortcuts.match(before: "ㅂㅂㄱ", shortcuts: shortcuts) == nil)
        XCTAssertTrue(TextShortcuts.match(before: "ㅂㄱ ", shortcuts: shortcuts) == nil)
        XCTAssertTrue(TextShortcuts.match(before: nil, shortcuts: shortcuts) == nil)
        XCTAssertEqual(TextShortcuts.match(before: "우리\n주소", shortcuts: shortcuts)?.trigger, "주소")
        XCTAssertTrue(TextShortcuts.validate(trigger: "ㄱㅅ", expansion: "감사합니다", existing: shortcuts) == nil)
        XCTAssertFalse(TextShortcuts.validate(trigger: "ㄱ ㅅ", expansion: "감사합니다", existing: shortcuts) == nil)
        XCTAssertFalse(TextShortcuts.validate(trigger: "ㅂㄱ", expansion: "또", existing: shortcuts) == nil)
        XCTAssertTrue(TextShortcuts.validate(trigger: "ㅂㄱ", expansion: "반가워요", existing: shortcuts, replacing: "ㅂㄱ") == nil)
        XCTAssertFalse(Snippets.validate("a", existing: ["a"]) == nil)
        XCTAssertFalse(Snippets.validate("  ", existing: []) == nil)
    }
    func testClipboardHistoryIsBoundedAndDeduplicated() {
        var history = ClipboardHistory(capacity: 3)
        for value in ["a", "b", "a", "", nil, "c", "d"] { history.add(value) }
        XCTAssertEqual(history.items, ["d", "c", "a"])
        history.add(String(repeating: "x", count: 2001)); XCTAssertEqual(history.items.count, 3)
        history.clear(); XCTAssertTrue(history.items.isEmpty)
    }
}

