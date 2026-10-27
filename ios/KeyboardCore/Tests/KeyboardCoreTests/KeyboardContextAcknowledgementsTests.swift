import XCTest
@testable import KeyboardCore

final class KeyboardContextAcknowledgementsTests: XCTestCase {
    private let id = UUID()
    private func context(_ before: String, after: String = "", document: UUID? = nil, epoch: UInt64 = 1) -> DocumentContext {
        DocumentContext(documentID: document ?? id, epoch: epoch, before: before, selected: nil, after: after)
    }
    func testDelayedOwnWriteIsRecognizedAcrossRequestRevisionsOnlyBriefly() {
        var tracker = KeyboardContextAcknowledgements()
        tracker.record(context("앞 "), now: 1); tracker.record(context("앞 가"), now: 1.001)
        XCTAssertTrue(tracker.contains(context("앞 ", epoch: 8), now: 1.05))
        XCTAssertFalse(tracker.contains(context("앞 "), now: 1.121))
    }
    func testCursorMovesDocumentChangesAndExternalEditsAreNotOwnAcknowledgements() {
        var tracker = KeyboardContextAcknowledgements(); tracker.record(context("가나"), now: 1)
        XCTAssertFalse(tracker.contains(context("가", after: "나"), now: 1.01))
        XCTAssertFalse(tracker.contains(context("가나", document: UUID()), now: 1.01))
        XCTAssertFalse(tracker.contains(context("다른 글"), now: 1.01))
        tracker.reset(); XCTAssertFalse(tracker.contains(context("가나"), now: 1.01))
    }
}
