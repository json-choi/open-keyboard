import XCTest
@testable import KeyboardCore

final class KeyboardTouchTests: XCTestCase {
    private let keys = [KeyboardTouchTarget(id: 0, x: 0, y: 0, width: 40, height: 44), KeyboardTouchTarget(id: 1, x: 46, y: 0, width: 40, height: 44), KeyboardTouchTarget(id: 2, x: 92, y: 0, width: 40, height: 44, group: 0)]
    func testGapsResolveAndSmallBoundaryWobbleDoesNotChangeKey() {
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 42, y: 20, targets: keys), 0)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 44, y: 20, targets: keys, current: 0, group: 1), 0)
        XCTAssertEqual(KeyboardTouchTarget.resolve(x: 53, y: 20, targets: keys, current: 0, group: 1), 1)
    }
    func testSlidesCannotTriggerControlKeysAndFarOutsideCancels() {
        XCTAssertNil(KeyboardTouchTarget.resolve(x: 110, y: 20, targets: keys, current: 1, group: 1))
        XCTAssertNil(KeyboardTouchTarget.resolve(x: -30, y: 20, targets: keys, current: 0, group: 1))
        XCTAssertNil(KeyboardTouchTarget.resolve(x: 20, y: 80, targets: keys, current: 0, group: 1))
    }
    func testShortReleaseDriftKeepsTheTappedLetter() {
        // Onto a control, past the keyboard edge and below the row: the tap still types its letter.
        XCTAssertEqual(KeyboardTouchTarget.follow(x: 100, y: 20, targets: keys, current: 1, group: 1), 1)
        XCTAssertEqual(KeyboardTouchTarget.follow(x: -14, y: 20, targets: keys, current: 0, group: 1), 0)
        XCTAssertEqual(KeyboardTouchTarget.follow(x: 20, y: 60, targets: keys, current: 0, group: 1), 0)
        XCTAssertEqual(KeyboardTouchTarget.follow(x: 21, y: 60, targets: keys, current: 0, group: 1, unit: 1.5), 0)
        // Letters still switch on a real slide, and a deliberate slide away still cancels.
        XCTAssertEqual(KeyboardTouchTarget.follow(x: 53, y: 20, targets: keys, current: 0, group: 1), 1)
        XCTAssertNil(KeyboardTouchTarget.follow(x: 110, y: 20, targets: keys, current: 1, group: 1))
        XCTAssertNil(KeyboardTouchTarget.follow(x: 20, y: 80, targets: keys, current: 0, group: 1))
        XCTAssertNil(KeyboardTouchTarget.follow(x: 100, y: 20, targets: keys, current: nil, group: 1))
        XCTAssertNil(KeyboardTouchTarget.follow(x: .nan, y: 20, targets: keys, current: 0, group: 1))
    }
    func testOverlappingFingersCommitInPressOrderOnlyOnce() {
        var sequence = KeyboardTouchSequence(); sequence.begin(7, key: 0); sequence.begin(3, key: 1)
        XCTAssertEqual(sequence.end(3).map(\.key), [0, 1]); XCTAssertTrue(sequence.end(7).isEmpty)
        XCTAssertTrue(sequence.pressedKeys.isEmpty)
    }
    func testSameKeyAcceptsTwoFingersAndPointerIdentifiersCanBeReused() {
        var sequence = KeyboardTouchSequence(); sequence.begin(2, key: 0); sequence.begin(9, key: 0)
        XCTAssertEqual(sequence.end(9).map(\.key), [0, 0]); sequence.begin(2, key: 1)
        XCTAssertEqual(sequence.end(2).map(\.key), [1])
    }
    func testMovingFingerCommitsFinalKeyAndCancellationNeverTypes() {
        var sequence = KeyboardTouchSequence(); sequence.begin(0, key: 0); sequence.move(0, key: 1)
        XCTAssertEqual(sequence.end(0).map(\.key), [1]); sequence.begin(4, key: 0); sequence.cancel(4)
        XCTAssertTrue(sequence.end(4).isEmpty); sequence.begin(8, key: 1); sequence.cancelAll()
        XCTAssertTrue(sequence.end(8).isEmpty)
    }
    func testLeavingAndReenteringKeyDoesNotLoseOrDuplicateInput() {
        var sequence = KeyboardTouchSequence(); sequence.begin(0, key: 0); sequence.move(0, key: nil)
        XCTAssertTrue(sequence.pressedKeys.isEmpty); sequence.move(0, key: 1)
        XCTAssertEqual(sequence.end(0).map(\.key), [1])
    }
    func testConsumedSpaceGestureStillFlushesOlderLetterWithoutAddingSpace() {
        var sequence = KeyboardTouchSequence(); sequence.begin(0, key: 0); sequence.begin(1, key: 5)
        sequence.move(1, key: nil); XCTAssertEqual(sequence.end(1).map(\.key), [0])
        XCTAssertTrue(sequence.end(0).isEmpty); XCTAssertTrue(sequence.end(1).isEmpty)
    }
    func testModifierPressFlushesOlderFingersWithoutDuplicatingTheirRelease() {
        var sequence = KeyboardTouchSequence(); sequence.begin(0, key: 0); sequence.begin(1, key: 1)
        XCTAssertEqual(sequence.flush().map(\.key), [0, 1]); XCTAssertTrue(sequence.end(0).isEmpty)
        XCTAssertTrue(sequence.end(1).isEmpty)
    }
    func testQuickSpaceSwipeDoesNotBecomeCursorMovement() {
        var gesture = KeyboardCursorGesture()
        XCTAssertEqual(gesture.update(dx: 40, dy: 0, elapsedMilliseconds: 100), 0)
        XCTAssertFalse(gesture.active)
        XCTAssertEqual(gesture.update(dx: 5, dy: 30, elapsedMilliseconds: 500), 0)
        XCTAssertFalse(gesture.active)
    }
    func testCursorDetentsDoNotOscillateAtTheStepBoundary() {
        var gesture = KeyboardCursorGesture()
        XCTAssertEqual(gesture.update(dx: 30, dy: 0, elapsedMilliseconds: 300), 1)
        XCTAssertTrue(gesture.active)
        for x in [29.9, 30.1, 29.0, 31.0] { XCTAssertEqual(gesture.update(dx: x, dy: 0, elapsedMilliseconds: 350), 0) }
        XCTAssertEqual(gesture.update(dx: 18, dy: 0, elapsedMilliseconds: 400), -1)
        XCTAssertEqual(gesture.update(dx: -6, dy: 0, elapsedMilliseconds: 450), -2)
    }
}
