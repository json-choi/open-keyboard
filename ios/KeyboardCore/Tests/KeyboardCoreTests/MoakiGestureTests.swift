import XCTest
@testable import KeyboardCore

final class MoakiGestureTests: XCTestCase {
    func testReferenceLayoutKeepsNarrowPunctuationAndNumberHints() {
        XCTAssertEqual(MoakiLayout.rows.map(\.count), [7, 7, 7, 6])
        XCTAssertEqual(MoakiLayout.rows[0], ["~", "ㅃ", "ㅉ", "ㄸ", "ㄲ", "ㅆ", "!"])
        XCTAssertEqual(MoakiLayout.rows[3], ["*", "ㅋ", "ㅌ", "ㅊ", "ㅍ", "⌫"])
        XCTAssertEqual(MoakiLayout.numbers["ㅂ"], "1"); XCTAssertEqual(MoakiLayout.numbers["ㅎ"], "0")
        XCTAssertEqual(MoakiLayout.consonants.count, 19)
        XCTAssertEqual(Set(MoakiLayout.rows.flatMap { $0 }).intersection(MoakiLayout.consonants), MoakiLayout.consonants)
        for row in 0..<4 { XCTAssertEqual(MoakiLayout.weights(row: row).reduce(0, +), 6.2, accuracy: 0.001) }
    }

    private func gesture(_ directions: String) -> MoakiGesture {
        var gesture = MoakiGesture(), x = 0.0, y = 0.0
        for direction in directions {
            let delta: (Double, Double)
            switch direction {
            case "R": delta = (40, 0)
            case "L": delta = (-40, 0)
            case "U": delta = (0, -40)
            case "D": delta = (0, 40)
            case "I": delta = (40, -40)
            default: delta = (40, 40)
            }
            x += delta.0; y += delta.1; gesture.move(x: x, y: y)
        }
        return gesture
    }
    func testEveryVowelAndMirroredDiagonals() {
        let cases = ["R":"ㅏ", "RL":"ㅐ", "RLR":"ㅑ", "RLRL":"ㅒ", "L":"ㅓ", "LR":"ㅔ", "LRL":"ㅕ", "LRLR":"ㅖ", "U":"ㅗ", "UR":"ㅘ", "URL":"ㅙ", "UD":"ㅚ", "UDU":"ㅛ", "D":"ㅜ", "DL":"ㅝ", "DLR":"ㅞ", "DU":"ㅟ", "DUD":"ㅠ", "E":"ㅡ", "EI":"ㅢ", "I":"ㅣ"]
        XCTAssertEqual(Set(cases.values).count, 21)
        for (directions, expected) in cases {
            XCTAssertEqual(gesture(directions).input(base: "ㄱ"), "ㄱ" + expected, directions)
            XCTAssertEqual(gesture(directions).input(base: ""), expected)
        }
        var left = MoakiGesture(); left.move(x: -40, y: -40); XCTAssertEqual(left.vowel, "ㅣ")
        left.move(x: -80, y: 0); XCTAssertNil(left.vowel)
        var down = MoakiGesture(); down.move(x: -40, y: 40); down.move(x: 0, y: 0); XCTAssertEqual(down.vowel, "ㅢ")
    }
    func testTapJitterLongStrokesAndInvalidPaths() {
        var tap = MoakiGesture(); tap.move(x: 5, y: -3); tap.move(x: -4, y: 2)
        XCTAssertEqual(tap.input(base: "ㄲ"), "ㄲ"); XCTAssertEqual(tap.input(base: ""), "ㅣ")
        XCTAssertEqual(gesture("RRRR").input(base: "ㄱ"), "ㄱㅏ")
        XCTAssertNil(gesture("RU").input(base: "ㄱ"))
        XCTAssertNil(gesture("RLRLRLRLRL").input(base: "ㄱ"))
    }
    func testAllInitialsComposeWithAllGestureVowels() {
        for (index, initial) in "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".enumerated() {
            for (v, path) in ["R","RL","RLR","RLRL","L","LR","LRL","LRLR","U","UR","URL","UD","UDU","D","DL","DLR","DU","DUD","E","EI","I"].enumerated() {
                var composer = HangulComposer()
                for jamo in gesture(path).input(base: String(initial))! { composer.append(jamo) }
                XCTAssertEqual(composer.text, String(UnicodeScalar(0xAC00 + (index * 21 + v) * 28)!))
            }
        }
    }
    func testRoundedCornerRecoversWithoutDroppingTheVowel() {
        var rounded = MoakiGesture()
        for point in [(0.0, -24.0), (8.0, -32.0), (10.0, -34.0), (24.0, -34.0)] { rounded.move(x: point.0, y: point.1) }
        XCTAssertEqual(rounded.input(base: "ㄱ"), "ㄱㅘ")
        var unfinished = MoakiGesture(); unfinished.move(x: 0, y: -24); unfinished.move(x: 10, y: -34)
        XCTAssertEqual(unfinished.input(base: "ㄱ"), "ㄱㅗ")
    }
    func testSmallTerminalWobbleKeepsTheLastVowelButSustainedWrongTurnsFail() {
        var wobble = MoakiGesture(); wobble.move(x: 24, y: 0); wobble.move(x: 34, y: -10)
        XCTAssertEqual(wobble.input(base: "ㄱ"), "ㄱㅏ")
        wobble.move(x: 34, y: -24)
        XCTAssertNil(wobble.input(base: "ㄱ"))
        var wrong = MoakiGesture(); wrong.move(x: 24, y: 0)
        for y in [12.0, 24, 36] { wrong.move(x: 24, y: -y) }
        XCTAssertNil(wrong.input(base: "ㄱ"))
    }
    func testActivationDistanceScalesAndClampsToKeySize() {
        XCTAssertEqual(MoakiGesture.activationDistance(keyWidth: 32, keyHeight: 32), 8)
        XCTAssertEqual(MoakiGesture.activationDistance(keyWidth: 48, keyHeight: 44), 10.56, accuracy: 0.001)
        XCTAssertEqual(MoakiGesture.activationDistance(keyWidth: 100, keyHeight: 100), 16)
        XCTAssertEqual(MoakiGesture.activationDistance(keyWidth: .nan, keyHeight: 44), 12)
    }
}
