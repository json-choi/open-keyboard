import XCTest
@testable import KeyboardCore

final class TypingAidsTests: XCTestCase {
    func testTapPredictionFollowsTheHangulAutomaton() throws {
        var prediction = KoreanTapPrediction()
        XCTAssertNil(prediction.reach(of: "ㅎ"), "Any key can start a word")
        prediction.record("ㅎ")
        XCTAssertEqual(try XCTUnwrap(prediction.reach(of: "ㅗ")), KeyboardTouchTarget.maxReach, accuracy: 1e-9, "An onset wants a vowel")
        XCTAssertEqual(try XCTUnwrap(prediction.reach(of: "ㅅ")), 0, accuracy: 1e-9)
        prediction.record("ㅗ")
        XCTAssertGreaterThan(try XCTUnwrap(prediction.reach(of: "ㅏ")), try XCTUnwrap(prediction.reach(of: "ㅓ")), "ㅗ can become ㅘ ㅙ ㅚ")
        XCTAssertGreaterThan(try XCTUnwrap(prediction.reach(of: "ㄴ")), try XCTUnwrap(prediction.reach(of: "ㅛ")), "…or take a final")
        prediction.record("ㅏ")
        XCTAssertGreaterThan(try XCTUnwrap(prediction.reach(of: "ㄴ")), try XCTUnwrap(prediction.reach(of: "ㅣ")), "화 is followed by a consonant")
        prediction.record("ㄹ")
        let open = KoreanTapPrediction.keys.compactMap { prediction.reach(of: String($0)) }
        XCTAssertEqual(open.count, 33)
        XCTAssertLessThan(open.max()! - open.min()!, 0.05, "After 활 a vowel, a second final or a new syllable are all plausible")
        prediction.record(" "); XCTAssertNil(prediction.reach(of: "ㅎ"))
        prediction.record("ㅉ"); XCTAssertNil(prediction.reach(of: "1"), "Not a dubeolsik key")
        XCTAssertEqual(try XCTUnwrap(prediction.reach(of: "ㅏ")), KeyboardTouchTarget.maxReach, accuracy: 1e-9)
        prediction.reset(); XCTAssertNil(prediction.reach(of: "ㅏ"))
    }
    func testLikelyKeyTakesAtMostAQuarterAndNeverTheMiddle() {
        let keys = [KeyboardTouchTarget(id: 0, x: 0, y: 0, width: 100, height: 120), KeyboardTouchTarget(id: 1, x: 100, y: 0, width: 100, height: 120), KeyboardTouchTarget(id: 2, x: 200, y: 0, width: 100, height: 120, group: 0)]
        let vowel = [0: 0.0, 1: KeyboardTouchTarget.maxReach]
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 95, y: 60, targets: keys), 0)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 95, y: 60, targets: keys, reach: vowel), 1)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 76, y: 60, targets: keys, reach: vowel), 1)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 74, y: 60, targets: keys, reach: vowel), 0)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 50, y: 5, targets: keys, reach: vowel), 0)
        XCTAssertEqual(KeyboardTouchTarget.follow(x: 95, y: 60, targets: keys, current: 1, reach: vowel), 1, "Lifting the finger keeps the predicted key")
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 99, y: 60, targets: keys, reach: [0: 0.2, 1: 0.2]), 0, "Equal reach keeps the drawn boundary")
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 201, y: 60, targets: keys, reach: [1: KeyboardTouchTarget.maxReach]), 2, "Controls never shrink")
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 74, y: 60, targets: keys, reach: [0: 0, 1: 9]), 0, "Reach is capped")
        let stacked = [KeyboardTouchTarget(id: 0, x: 0, y: 0, width: 100, height: 120), KeyboardTouchTarget(id: 1, x: 0, y: 120, width: 100, height: 120, row: 1)]
        let below = [0: 0.0, 1: KeyboardTouchTarget.maxReach]
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 50, y: 106, targets: stacked, reach: below), 1, "Rows trade half as much height")
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 50, y: 104, targets: stacked, reach: below), 0)
    }
    func testEveryPointOfADubeolsikKeyboardTypesAKeyAndKeyCentresHold() {
        // iPhone-sized dubeolsik rows: 6pt gaps between keys and 10pt between rows, as drawn on iOS.
        var keys: [KeyboardTouchTarget] = [], values: [String?] = []
        func row(_ y: Double, _ left: Double, _ width: Double, _ labels: [String?], _ weights: [Double]) {
            let unit = (width - 6 * Double(labels.count - 1)) / weights.reduce(0, +); var x = left
            for (index, label) in labels.enumerated() {
                keys.append(KeyboardTouchTarget(id: keys.count, x: x, y: y, width: unit * weights[index], height: 44, group: label == nil ? 0 : 1, row: Int(y / 54)))
                values.append(label); x += unit * weights[index] + 6
            }
        }
        row(0, 0, 380, "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ".map { String($0) }, Array(repeating: 1, count: 10))
        row(54, 19, 342, "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".map { String($0) }, Array(repeating: 1, count: 9))
        row(108, 0, 380, [nil] + "ㅋㅌㅊㅍㅠㅜㅡ".map { String($0) } + [nil], [1.4] + Array(repeating: 1, count: 7) + [1.4])
        row(162, 0, 380, [nil, nil, nil, nil], [1.3, 1, 6, 1.4])
        // Edge keys own the inset beside them, as both apps extend them.
        let first = keys[10], last = keys[18]
        keys[10] = KeyboardTouchTarget(id: 10, x: 0, y: first.y, width: first.x + first.width, height: first.height, row: first.row)
        keys[18] = KeyboardTouchTarget(id: 18, x: last.x, y: last.y, width: 380 - last.x, height: last.height, row: last.row)
        for context in ["", "ㅎ", "ㅎㅗ", "ㅎㅗㅏ", "ㅎㅗㅏㄹ", "ㄷㅏㄹㄱ", "ㅋ", "ㅇㅡ"] {
            var prediction = KoreanTapPrediction()
            for jamo in context { prediction.record(String(jamo)) }
            var reach: [Int: Double] = [:]
            for (id, value) in values.enumerated() { if let value, let share = prediction.reach(of: value) { reach[id] = share } }
            for y in stride(from: -8.0, through: 214, by: 1) {
                for x in stride(from: -8.0, through: 388, by: 1) where KeyboardTouchTarget.resolve(x: x, y: y, targets: keys, reach: reach) == nil {
                    XCTFail("\(context) (\(x), \(y)) types nothing"); return
                }
            }
            // The middle half of the width and the middle three quarters of the height always type the key.
            for key in keys { for fx in [0.25, 0.5, 0.75] { for fy in [0.125, 0.5, 0.875] {
                XCTAssertEqual(KeyboardTouchTarget.resolve(x: key.x + key.width * fx, y: key.y + key.height * fy, targets: keys, reach: reach), key.id, "\(context) \(values[key.id] ?? "control")")
            } } }
        }
    }
    func testDeleteRepeatAcceleratesThenDeletesWords() {
        XCTAssertEqual(DeleteRepeat.step(repeats: 1, held: 0.5), .characters(1))
        XCTAssertEqual(DeleteRepeat.step(repeats: 21, held: 2), .characters(2))
        XCTAssertEqual(DeleteRepeat.step(repeats: 30, held: 3.1), .word)
        XCTAssertEqual(DeleteRepeat.lastWord(in: "안녕하세요 반갑습니다  "), "반갑습니다  ")
        XCTAssertEqual(DeleteRepeat.lastWord(in: "좋아요, 정말!"), "정말!")
        XCTAssertEqual(DeleteRepeat.lastWord(in: "👨‍👩‍👧‍👦 가족"), "가족")
        XCTAssertEqual(DeleteRepeat.lastWord(in: ""), "")
    }
    func testDeleteSlideRemovesAndRestoresWholeCharacters() {
        var slide = DeleteSlide(before: "가족👨‍👩‍👧‍👦요")
        XCTAssertEqual(DeleteSlide.count(dx: -35), 3); XCTAssertEqual(DeleteSlide.count(dx: 12), 0)
        var r = slide.move(to: 3)
        XCTAssertEqual(r.delete, 3); XCTAssertEqual(r.restore, "")
        r = slide.move(to: 1)
        XCTAssertEqual(r.delete, 0); XCTAssertEqual(r.restore, "족👨‍👩‍👧‍👦")
        r = slide.move(to: 9)
        XCTAssertEqual(r.delete, 3, "Only what was there is removed"); XCTAssertEqual(slide.removed, 4)
        r = slide.move(to: 0)
        XCTAssertEqual(r.restore, "가족👨‍👩‍👧‍👦요")
    }
}
