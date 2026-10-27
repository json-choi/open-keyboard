import Foundation
import XCTest
@testable import KeyboardCore

final class KeyboardTouchReplayTests: XCTestCase {
    private struct Contact { var key: Int?; let group: Int }
    private func legacy(_ x: Double, _ y: Double, _ keys: [KeyboardTouchTarget], _ current: Int?, _ group: Int?) -> Int? {
        guard x >= keys.map(\.x).min()! - 8, x <= keys.map({ $0.x + $0.width }).max()! + 8,
              y >= keys.map(\.y).min()! - 8, y <= keys.map({ $0.y + $0.height }).max()! + 8 else { return nil }
        var nearest: KeyboardTouchTarget?, distance = Double.infinity, retained: Int?
        for key in keys {
            if key.id == current, group == nil || key.group == group,
               x >= key.x - 4, x <= key.x + key.width + 4, y >= key.y - 4, y <= key.y + key.height + 4 { retained = key.id }
            let dx = max(key.x - x, 0, x - key.x - key.width), dy = max(key.y - y, 0, y - key.y - key.height)
            let value = dx * dx + dy * dy
            if value < distance { nearest = key; distance = value }
        }
        if let retained { return retained }
        return nearest.flatMap { group == nil || $0.group == group ? $0.id : nil }
    }
    func testSharedReplayMatchesIntendedKeysAndFrozenBaseline() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "keyboard_touch_replay", withExtension: "tsv", subdirectory: "Fixtures"))
        let input = try String(contentsOf: url, encoding: .utf8)
        var cases = 0, improvements = 0
        for line in input.split(separator: "\n") where !line.hasPrefix("#") {
            let cells = line.split(separator: "|").map(String.init)
            XCTAssertEqual(cells.count, 6)
            let keys = cells[1].split(separator: ";").map { text -> KeyboardTouchTarget in
                let n = text.split(separator: ",").map { Double($0)! }
                return .init(id: Int(n[0]), x: n[1], y: n[2], width: n[3], height: n[4], group: Int(n[5]), row: Int(n[6]))
            }
            var corrections: [Int: KeyboardTouchCorrection] = [:]
            if cells[2] != "_" { for text in cells[2].split(separator: ";") {
                let n = text.split(separator: ",").map { Double($0)! }
                corrections[Int(n[0])] = .init(verticalOffset: n[1], radiusScale: n[2])
            } }
            func expected(_ value: String) -> [Int] { value == "_" ? [] : value.split(separator: ",").map { Int($0)! } }
            func replay(useLegacy: Bool, scale: Double = 1) -> [Int] {
                let targets = keys.map { KeyboardTouchTarget(id: $0.id, x: $0.x * scale, y: $0.y * scale, width: $0.width * scale, height: $0.height * scale, group: $0.group, row: $0.row) }
                var contacts: [Int: Contact] = [:], sequence = KeyboardTouchSequence(), output: [Int] = []
                for event in cells[3].split(separator: ";") {
                    let e = event.split(separator: ",").map(String.init), pointer = Int(e[1])!, x = Double(e[2])! * scale, y = Double(e[3])! * scale
                    func resolve(_ current: Int?, _ group: Int?) -> Int? {
                        useLegacy ? legacy(x, y, targets, current, group) : KeyboardTouchTarget.resolve(x: x, y: y, targets: targets, current: current, group: group, outerMargin: 8 * scale, unit: scale, corrections: corrections)
                    }
                    if e[0] == "D" {
                        if let key = resolve(nil, nil), let target = targets.first(where: { $0.id == key }) {
                            contacts[pointer] = Contact(key: key, group: target.group); sequence.begin(pointer, key: key)
                        }
                    } else if e[0] == "C" { contacts.removeValue(forKey: pointer); sequence.cancel(pointer) }
                    else if var contact = contacts[pointer] {
                        if sequence.contains(pointer) {
                            contact.key = resolve(contact.key, contact.group); contacts[pointer] = contact
                            sequence.move(pointer, key: contact.key)
                        }
                        if e[0] == "U" { output += sequence.end(pointer).map(\.key); contacts.removeValue(forKey: pointer) }
                    }
                }
                return output
            }
            let intended = expected(cells[4]), previous = expected(cells[5])
            XCTAssertEqual(replay(useLegacy: true), previous, cells[0] + " legacy")
            for scale in [1.0, 1.5, 2, 3] { XCTAssertEqual(replay(useLegacy: false, scale: scale), intended, cells[0] + " scale=\(scale)") }
            if previous != intended { improvements += 1 }; cases += 1
        }
        XCTAssertEqual(cases, 16); XCTAssertEqual(improvements, 5)
    }
    func testCandidatesAreLocalStableAndRespectGroups() {
        let keys = [KeyboardTouchTarget(id: 0, x: 0, y: 0, width: 40, height: 44), .init(id: 1, x: 46, y: 0, width: 40, height: 44), .init(id: 2, x: 92, y: 0, width: 40, height: 44, group: 0)]
        XCTAssertEqual(KeyboardTouchTarget.candidates(x: 43, y: 20, targets: keys, group: 1), [0, 1])
        XCTAssertEqual(KeyboardTouchTarget.candidates(x: 43, y: 20, targets: keys.reversed(), group: 1), [0, 1])
        XCTAssertEqual(KeyboardTouchTarget.candidates(x: 20, y: 20, targets: keys, group: 1), [0])
        XCTAssertTrue(KeyboardTouchTarget.candidates(x: .nan, y: 20, targets: keys).isEmpty)
        XCTAssertTrue(KeyboardTouchTarget.candidates(x: 20, y: 20, targets: keys, limit: 0).isEmpty)
        XCTAssertNil(KeyboardTouchTarget.resolve(x: .infinity, y: 20, targets: keys))
        let invalid = KeyboardTouchTarget(id: 99, x: .nan, y: 0, width: 0, height: 44)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 20, y: 20, targets: [invalid] + keys), 0)
    }
    func testCalibrationIsBoundedAndDoesNotMoveControls() {
        let invalid = KeyboardTouchCorrection(verticalOffset: .nan, radiusScale: .infinity)
        XCTAssertEqual(invalid.verticalOffset, 0); XCTAssertEqual(invalid.radiusScale, 1)
        let bounded = KeyboardTouchCorrection(verticalOffset: 100, radiusScale: -1)
        XCTAssertEqual(bounded.verticalOffset, 0.25); XCTAssertEqual(bounded.radiusScale, 0.75)
        let control = KeyboardTouchTarget(id: 9, x: 0, y: 0, width: 40, height: 44, group: 0)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 20, y: -7, targets: [control], corrections: [0: bounded]), 9)
        let overlapping = KeyboardTouchTarget(id: 1, x: 0, y: -48, width: 40, height: 44, row: 1)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 20, y: 2, targets: [overlapping, control], corrections: [1: bounded]), 9)
        XCTAssertNil(KeyboardTouchTarget.resolve(x: 20, y: 2, targets: [overlapping, control], group: 1, corrections: [1: bounded]))
    }
}
