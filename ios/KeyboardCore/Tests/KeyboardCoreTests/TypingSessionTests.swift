import XCTest
@testable import KeyboardCore

/// Korean composition against a fake host that can lag, drop writes or omit its marked text.
@MainActor final class TypingSessionTests: XCTestCase {
    private final class Host: PartialEditPort {
        var text: String; var cursor: Int; var epoch: UInt64 = 1; var id = UUID()
        var reads = 0
        var supportsMarkedComposition = false
        var excludesMarkedText = false
        var markedRange: NSRange?
        var markedWrites = 0
        var commits = 0
        func setMarkedComposition(_ value: String) {
            changing(); markedWrites += 1
            let range = markedRange ?? NSRange(location: cursor, length: 0)
            text = (text as NSString).replacingCharacters(in: range, with: value)
            markedRange = NSRange(location: range.location, length: value.utf16.count)
            cursor = range.location + value.utf16.count
        }
        var committed: [String] = []
        var reportsHasText = false
        var forcedHasText: Bool?
        var hasText: Bool? { forcedHasText ?? (reportsHasText ? !text.isEmpty : nil) }
        func commitMarkedComposition(_ text: String) { commits += 1; committed.append(text); markedRange = nil }
        func endMarkedComposition() { commits += 1; markedRange = nil }
        var nilEmptyContext = false
        var delayedReads = 0
        private var stale: DocumentContext?
        private var staleReads = 0
        var ignoreInsert = false
        var handlesReturn = false
        var submissions: [String] = []
        var changeEpochAfterInsert = false
        var deletes = 0; var inserted: [String] = []; var ignoreMove = false; var ignoreDelete = false; var ignoreDeleteAfterInsert = false
        init(_ text: String) { self.text = text; cursor = text.utf16.count }
        func read() -> DocumentContext? {
            reads += 1
            if staleReads > 0 { staleReads -= 1; return stale }
            return context()
        }
        private func context() -> DocumentContext {
            let value = text as NSString
            if excludesMarkedText, let markedRange, cursor == NSMaxRange(markedRange) {
                return DocumentContext(documentID: id, epoch: epoch, before: value.substring(to: markedRange.location), selected: nil, after: value.substring(from: cursor))
            }
            return DocumentContext(documentID: id, epoch: epoch, before: nilEmptyContext && cursor == 0 ? nil : value.substring(to: cursor), selected: nil, after: nilEmptyContext && cursor == value.length ? nil : value.substring(from: cursor))
        }
        private func changing() { stale = context(); staleReads = delayedReads }
        func move(_ offset: Int) { if !ignoreMove { changing(); cursor = min(max(0, cursor + offset), text.utf16.count) } }
        func deleteBackward() {
            deletes += 1; guard !ignoreDelete, cursor > 0 else { return }
            changing()
            let before = (text as NSString).substring(to: cursor); let length = String(before.last!).utf16.count
            text = (text as NSString).replacingCharacters(in: NSRange(location: cursor - length, length: length), with: ""); cursor -= length
        }
        func insert(_ value: String) {
            guard !ignoreInsert else { return }
            if handlesReturn, value == "\n" { submissions.append(text); return }
            markedRange = nil
            changing()
            if ignoreDeleteAfterInsert { ignoreDelete = true }
            inserted.append(value); text = (text as NSString).replacingCharacters(in: NSRange(location: cursor, length: 0), with: value); cursor += value.utf16.count
            if changeEpochAfterInsert { epoch += 1 }
        }
    }
    func testKoreanSpaceReturnAndNextWordPreserveCommittedDraft() {
        let host = Host("앞 문장 👨‍👩‍👧‍👦. "), typing = KoreanTypingSession()
        for key in "ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅅㅔㅇㅛ" {
            host.epoch += 1
            typing.input(String(key), language: "ko", layout: "dubeolsik", port: host)
        }
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕핫세요")
        let deletes = host.deletes
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.deletes, deletes, "Space must only insert a space")
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕핫세요 ")
        for key in "ㅂㅏㄴㄱㅏㅇㅜㅓㅇㅛ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕핫세요 반가워요")
        typing.input("\n", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕핫세요 반가워요\n")
    }
    func testSearchReturnCommitsKoreanWithoutInventingANewlineInTheNextComposition() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.handlesReturn = true
        for key in "ㄱㅓㅁㅅㅐㄱ" {
            XCTAssertEqual(gate.submit(.input(String(key), language: "ko", layout: "dubeolsik"), port: host, now: 1), .applied)
        }
        XCTAssertEqual(gate.submit(.returnAction, port: host, now: 2), .applied)
        XCTAssertEqual(host.submissions, ["검색"]); XCTAssertEqual(host.text, "검색")
        XCTAssertNil(host.markedRange); XCTAssertFalse(typing.hasActiveComposition)
        for key in "ㄱㅏ" { _ = gate.submit(.input(String(key), language: "ko", layout: "dubeolsik"), port: host, now: 3) }
        XCTAssertEqual(host.text, "검색가"); XCTAssertTrue(typing.hasActiveComposition)
    }
    func testMarkedCompositionUpdatesWithoutIntermediateDeletesOrCursorMoves() {
        let host = Host("앞 문장 👨‍👩‍👧‍👦. "), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true
        let keys = "ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ"
        for key in keys { host.epoch += 1; typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕하세요")
        XCTAssertEqual(host.markedWrites, keys.count)
        XCTAssertEqual(host.deletes, 0); XCTAssertEqual(host.inserted, [])
        XCTAssertEqual(host.cursor, host.text.utf16.count)
        typing.delete(port: host)
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕하셍")
        XCTAssertEqual(host.deletes, 0)
        typing.input("ㅛ", language: "ko", layout: "dubeolsik", port: host)
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦. 안녕하세요 ")
        XCTAssertNil(host.markedRange); XCTAssertEqual(host.inserted, [" "])
        XCTAssertEqual(host.commits, 1)
    }
    func testMarkedCompositionCommitsBeforeExternalPasteAndNewWord() {
        let host = Host(""), typing = KoreanTypingSession(); host.supportsMarkedComposition = true
        for key in "ㄱㅏㅂㅅ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "값")
        host.insert("붙여넣기")
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        typing.input("ㅏ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "값붙여넣기가"); XCTAssertEqual(host.deletes, 0)
        typing.finish(port: host); XCTAssertNil(host.markedRange)
    }
    func testLaggingHostReadsKeepEverySyllableComposed() {
        // A keyboard proxy reflects writes late: reads can show the text from before the last keys.
        for delay in 1...3 {
            let host = Host(""), typing = KoreanTypingSession()
            host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.delayedReads = delay
            for key in "ㅈㅔㄱㅏ ㅉㅏㅇㅇㅣ ㄱㄱㅏ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
            typing.delete(port: host); typing.delete(port: host); typing.input("ㅏ", language: "ko", layout: "dubeolsik", port: host)
            typing.finish(port: host)
            XCTAssertEqual(host.text, "제가 짱이 가", "delay \(delay)")
            XCTAssertEqual(host.deletes, 0, "delay \(delay)")
        }
    }
    func testLaggingHostStillEndsCompositionAfterARealCursorMove() {
        let host = Host("앞 "), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.delayedReads = 1
        for key in "ㅎㅏㄴ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        _ = host.read(); host.cursor = 0
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        typing.finish(port: host)
        XCTAssertEqual(host.text, "ㄱ앞 한"); XCTAssertEqual(host.deletes, 0)
    }
    func testSentAndClearedFieldNeverGetsTheComposingWordBack() {
        let host = Host(""), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄴㅔ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "네")
        // The host sends the message and clears the field, marked text included.
        host.text = ""; host.cursor = 0; host.markedRange = nil
        typing.finish(port: host)
        XCTAssertEqual(host.committed, []); XCTAssertEqual(host.text, "")
        typing.input("ㅇ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "ㅇ"); XCTAssertEqual(host.committed, [])
    }
    func testComposingWordStillInTheFieldIsCommitted() {
        let host = Host(""), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄴㅔ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        typing.finish(port: host)
        XCTAssertEqual(host.committed, ["네"]); XCTAssertEqual(host.text, "네")
    }
    func testTypingImmediatelyAfterSendStartsANewCompositionWithoutAHostCallback() {
        for (layout, keys, next) in [("dubeolsik", ["ㄴ", "ㅔ"], ["ㄱ", "ㅏ"]),
                                     ("moaki", ["ㄴㅔ"], ["ㄱㅏ"]),
                                     ("cheonjiin", ["ㄴㄹ", "ㅣ"], ["ㄱㅋㄲ", "ㅣ"])] {
            let host = Host(""), typing = KoreanTypingSession()
            host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
            for key in keys { typing.input(key, language: "ko", layout: layout, port: host) }
            XCTAssertFalse(host.text.isEmpty)
            // Sending does not necessarily dismiss the keyboard or deliver a textDidChange before the next key.
            host.text = ""; host.cursor = 0; host.markedRange = nil
            let gate = KeyboardHostInputGate(typing: typing)
            for key in next { XCTAssertEqual(gate.submit(.input(key, language: "ko", layout: layout), port: host, now: 0), .waiting) }
            XCTAssertEqual(host.text, "")
            guard case .cleared = gate.observe(port: host, now: 0.101) else { return XCTFail("The cleared host must start a new word") }
            XCTAssertEqual(host.text, layout == "cheonjiin" ? "기" : "가", layout)
            XCTAssertEqual(host.committed, [], layout)
        }
    }
    func testDeleteImmediatelyAfterSendDoesNotRestoreThePreviousComposition() {
        let host = Host(""), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㅇㅏㄴㄴㅕㅇ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.text = ""; host.cursor = 0; host.markedRange = nil
        let gate = KeyboardHostInputGate(typing: typing)
        XCTAssertEqual(gate.submit(.delete, port: host, now: 0), .waiting)
        XCTAssertEqual(gate.observe(port: host, now: 0.101), .cleared(replayed: [.delete]))
        XCTAssertEqual(host.text, ""); XCTAssertEqual(host.committed, [])
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "ㄱ")
    }
    func testClearedFieldIsNotProjectedOrRecognizedAsItsOldMarkedWord() {
        let host = Host(""), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄴㅔ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(typing.includingComposition(in: host.read())?.before, "네")
        host.text = ""; host.cursor = 0; host.markedRange = nil
        let empty = host.read()
        let gate = KeyboardHostInputGate(typing: typing)
        XCTAssertEqual(gate.observe(port: host, now: 0), .waiting)
        XCTAssertTrue(gate.isWaiting, "The controller must suspend AI snapshots while presence is unresolved")
        XCTAssertEqual(gate.observe(port: host, now: 0.101), .cleared(replayed: []))
        XCTAssertEqual(typing.includingComposition(in: empty), empty)
        XCTAssertFalse(typing.recognizes(empty))
        XCTAssertEqual(host.text, ""); XCTAssertEqual(host.committed, [])
    }
    func testTransientEmptyFlagQueuesTheVowelWithoutBreakingTheLiveSyllable() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        XCTAssertEqual(gate.submit(.input("ㄱ", language: "ko", layout: "dubeolsik"), port: host, now: 0), .applied)
        host.forcedHasText = false
        XCTAssertEqual(gate.submit(.input("ㅏ", language: "ko", layout: "dubeolsik"), port: host, now: 0.01), .waiting)
        XCTAssertEqual(host.text, "ㄱ"); XCTAssertNotNil(host.markedRange); XCTAssertEqual(host.commits, 0)
        XCTAssertEqual(gate.observe(port: host, now: 0.05), .waiting)
        host.forcedHasText = true
        XCTAssertEqual(gate.observe(port: host, now: 0.06), .applied)
        XCTAssertEqual(host.text, "가"); XCTAssertEqual(host.commits, 0)
        XCTAssertEqual(gate.observe(port: host, now: 0.07), .applied)
        XCTAssertEqual(host.text, "가", "A recheck must never replay the vowel twice")
    }
    func testTransientEmptyFlagBeforeDeletePreservesTheRestOfTheSyllable() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄱㅏㄴ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.forcedHasText = false
        XCTAssertEqual(gate.submit(.delete, port: host, now: 0), .waiting)
        XCTAssertEqual(host.text, "간")
        host.forcedHasText = true
        XCTAssertEqual(gate.observe(port: host, now: 0.02), .applied)
        XCTAssertEqual(host.text, "가"); XCTAssertEqual(host.deletes, 0); XCTAssertEqual(host.commits, 0)
    }
    func testKeysAndDeletesDuringPresenceRecheckKeepTheirOrderAndOccurOnlyOnce() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㅇㅏㄴㄴㅕㅇ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.forcedHasText = false
        let events: [KeyboardHostInputGate.Event] = [.input("ㅎ", language: "ko", layout: "dubeolsik"), .input("ㅏ", language: "ko", layout: "dubeolsik"), .delete, .input("ㅔ", language: "ko", layout: "dubeolsik")]
        for (i, event) in events.enumerated() { XCTAssertEqual(gate.submit(event, port: host, now: Double(i) / 100), .waiting) }
        XCTAssertEqual(host.text, "안녕"); XCTAssertEqual(host.commits, 0)
        host.forcedHasText = true
        XCTAssertEqual(gate.observe(port: host, now: 0.04), .applied)
        XCTAssertEqual(host.text, "안녕헤"); XCTAssertFalse(gate.hasPendingEvents)
        XCTAssertEqual(gate.observe(port: host, now: 0.2), .applied)
        XCTAssertEqual(host.text, "안녕헤")
    }
    func testConfirmedSendReplaysOnlyNewKeysAndDeletes() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄴㅔ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.text = ""; host.cursor = 0; host.markedRange = nil
        let events: [KeyboardHostInputGate.Event] = [.input("ㄱ", language: "ko", layout: "dubeolsik"), .input("ㅏ", language: "ko", layout: "dubeolsik"), .input("ㄴ", language: "ko", layout: "dubeolsik"), .delete]
        for (i, event) in events.enumerated() { XCTAssertEqual(gate.submit(event, port: host, now: Double(i) / 100), .waiting) }
        XCTAssertEqual(gate.observe(port: host, now: 0.101), .cleared(replayed: events))
        XCTAssertEqual(host.text, "가"); XCTAssertEqual(host.committed, [])
        XCTAssertEqual(gate.observe(port: host, now: 0.2), .applied); XCTAssertEqual(host.text, "가")
    }
    func testVisibleTextOverridesAStaleEmptyFlagWithoutWaiting() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.reportsHasText = true
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        host.forcedHasText = false
        XCTAssertEqual(gate.submit(.input("ㅏ", language: "ko", layout: "dubeolsik"), port: host, now: 0), .applied)
        XCTAssertEqual(host.text, "가"); XCTAssertFalse(gate.isWaiting)
    }
    func testPendingKeysNeverMoveToAnotherDocument() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        host.forcedHasText = false
        XCTAssertEqual(gate.submit(.input("ㅏ", language: "ko", layout: "dubeolsik"), port: host, now: 0), .waiting)
        host.id = UUID(); host.text = "다른 입력창"; host.cursor = host.text.utf16.count; host.markedRange = nil; host.forcedHasText = true
        XCTAssertEqual(gate.observe(port: host, now: 0.02), .abandoned)
        XCTAssertEqual(host.text, "다른 입력창"); XCTAssertEqual(host.commits, 0)
        XCTAssertFalse(gate.hasPendingEvents); XCTAssertFalse(typing.hasHostState)
    }
    func testPendingKeysNeverMoveToAnExternalCursorPositionInTheSameDocument() {
        let host = Host("앞 "), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        // The proxy temporarily reports empty contexts as well as an empty presence flag.
        let original = host.text
        host.text = ""; host.cursor = 0; host.markedRange = nil
        XCTAssertEqual(gate.submit(.input("ㅏ", language: "ko", layout: "dubeolsik"), port: host, now: 0), .waiting)
        host.text = original; host.cursor = 0
        XCTAssertEqual(gate.observe(port: host, now: 0.02), .abandoned)
        XCTAssertEqual(host.text, original); XCTAssertEqual(host.cursor, 0)
        XCTAssertFalse(gate.hasPendingEvents)
    }
    func testQueuedCheonjiinKeyUsesItsPressTimeInsteadOfItsReplayTime() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(gate.submit(.input("ㄱㅋㄲ", language: "ko", layout: "cheonjiin"), port: host, now: 0, inputTime: start), .applied)
        host.forcedHasText = false
        XCTAssertEqual(gate.submit(.input("ㄱㅋㄲ", language: "ko", layout: "cheonjiin"), port: host, now: 0.79, inputTime: start.addingTimeInterval(0.79)), .waiting)
        host.forcedHasText = true
        XCTAssertEqual(gate.observe(port: host, now: 0.88), .applied)
        XCTAssertEqual(host.text, "ㅋ", "The press was inside the 0.8-second cycle even though replay was later")
    }
    func testHeldWordDeleteKeepsItsPlaceAmongQueuedKeysAfterSend() {
        let host = Host(""), typing = KoreanTypingSession(), gate = KeyboardHostInputGate(typing: typing)
        host.supportsMarkedComposition = true; host.excludesMarkedText = true; host.reportsHasText = true
        for key in "ㄴㅔ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.text = ""; host.cursor = 0; host.markedRange = nil
        let events: [KeyboardHostInputGate.Event] = [.input("ㄱ", language: "ko", layout: "dubeolsik"), .input("ㅏ", language: "ko", layout: "dubeolsik"), .deleteWord, .input("ㄴ", language: "ko", layout: "dubeolsik"), .input("ㅏ", language: "ko", layout: "dubeolsik")]
        for (i, event) in events.enumerated() { XCTAssertEqual(gate.submit(event, port: host, now: Double(i) / 100), .waiting) }
        XCTAssertEqual(gate.observe(port: host, now: 0.101), .cleared(replayed: events))
        XCTAssertEqual(host.text, "나"); XCTAssertFalse(gate.hasPendingEvents)
    }
    func testEndingMarkedCompositionAfterACursorChangeNeverCommitsAtTheNewPosition() {
        let host = Host("앞 "), typing = KoreanTypingSession()
        host.supportsMarkedComposition = true; host.excludesMarkedText = true
        for key in "ㅎㅏㄴ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        host.cursor = 0
        let before = host.text
        typing.finish(port: host)
        XCTAssertEqual(host.text, before); XCTAssertEqual(host.cursor, 0)
        XCTAssertNil(host.markedRange)
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "ㄱ앞 한")
    }
    func testSpaceAndLatinInputDoNotReadTheHostToInsertUnchangedText() {
        let host = Host("안녕"), typing = KoreanTypingSession()
        for value in [" ", "a", "b", "\n"] { typing.input(value, language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "안녕 ab\n"); XCTAssertEqual(host.reads, 0); XCTAssertEqual(host.deletes, 0)
    }
    func testMarkedCompositionInTheMiddlePreservesFollowingTextAndNewCursor() {
        let host = Host("앞 뒤 👨‍👩‍👧‍👦"), typing = KoreanTypingSession()
        host.cursor = 2; host.supportsMarkedComposition = true
        for key in "ㅎㅏㄴㄱㅡㄹ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "앞 한글뒤 👨‍👩‍👧‍👦"); XCTAssertEqual(host.cursor, 4)
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "앞 한글 뒤 👨‍👩‍👧‍👦"); XCTAssertEqual(host.cursor, 5)
        host.cursor = host.text.utf16.count
        for key in "ㄱㅏ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "앞 한글 뒤 👨‍👩‍👧‍👦가")
        XCTAssertEqual(host.deletes, 0)
    }
    func testProxyThatExcludesMarkedTextComposesAndPublishesItsOwnedText() {
        let host = Host("앞 뒤"), typing = KoreanTypingSession()
        host.cursor = 2; host.supportsMarkedComposition = true; host.excludesMarkedText = true
        for key in "ㅇㅏㄴㄴㅕㅇ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "앞 안녕뒤")
        XCTAssertEqual(host.read()?.before, "앞 ")
        XCTAssertEqual(typing.includingComposition(in: host.read())?.before, "앞 안녕")
        XCTAssertEqual(typing.includingComposition(in: host.read())?.after, "뒤")
        var external = host.read()!; external.before = "다른 위치"
        XCTAssertEqual(typing.includingComposition(in: external), external)
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "앞 안녕 뒤"); XCTAssertNil(host.markedRange)
        XCTAssertEqual(host.deletes, 0)
    }
    func testMoakiSyllablesFinalsDeletionAndSpacePreserveDraft() {
        let host = Host("앞 문장 👨‍👩‍👧‍👦 "), typing = KoreanTypingSession()
        for value in ["ㅇㅏ", "ㄴ", "ㄴㅕ", "ㅇ", "ㅎㅏ", "ㅅㅔ", "ㅇㅛ"] {
            typing.input(value, language: "ko", layout: "moaki", port: host)
        }
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦 안녕하세요")
        typing.delete(port: host); XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦 안녕하셍")
        typing.input("ㅛ", language: "ko", layout: "moaki", port: host)
        let deletes = host.deletes
        typing.input(" ", language: "ko", layout: "moaki", port: host)
        XCTAssertEqual(host.deletes, deletes); XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦 안녕하세요 ")
        for value in ["ㄱㅏ", "ㅂ", "ㅅ", "ㅇㅣ"] { typing.input(value, language: "ko", layout: "moaki", port: host) }
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦 안녕하세요 값이")
        host.insert("붙여넣기")
        typing.input("ㄱㅏ", language: "ko", layout: "moaki", port: host)
        XCTAssertEqual(host.text, "앞 문장 👨‍👩‍👧‍👦 안녕하세요 값이붙여넣기가")
    }
    func testKoreanDeletionAndHostChangesDoNotOverwriteUnownedText() {
        let host = Host("👨‍👩‍👧‍👦 "), typing = KoreanTypingSession()
        for key in "ㄱㅏㅂㅅ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "👨‍👩‍👧‍👦 값")
        typing.delete(port: host); XCTAssertEqual(host.text, "👨‍👩‍👧‍👦 갑")
        host.insert("붙여넣기")
        typing.input("ㅇ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "👨‍👩‍👧‍👦 갑붙여넣기ㅇ")
        typing.finish()
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "👨‍👩‍👧‍👦 갑붙여넣기ㅇ ")
    }
    func testUnacknowledgedCompositionDeletionStopsWithoutRecoveryWrites() {
        let host = Host("이전 문장 "), typing = KoreanTypingSession()
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        host.ignoreDelete = true
        typing.input("ㅏ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "이전 문장 ㄱ")
        XCTAssertEqual(host.inserted, ["ㄱ"])
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "이전 문장 ㄱ ")
    }
    func testKoreanTypingAcceptsNilContextAtDocumentEdges() {
        let host = Host(""), typing = KoreanTypingSession(); host.nilEmptyContext = true
        for key in "ㅇㅏㄴㄴㅕㅇ" { typing.input(String(key), language: "ko", layout: "dubeolsik", port: host) }
        XCTAssertEqual(host.text, "안녕")
        typing.input(" ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "안녕 ")
    }
    func testCheonjiinSpacePreservesTextAndCycle() {
        let host = Host(""), typing = KoreanTypingSession()
        for key in ["ㄱㅋㄲ", "ㅣ", "ㆍ"] { typing.input(key, language: "ko", layout: "cheonjiin", port: host) }
        XCTAssertEqual(host.text, "가")
        typing.input(" ", language: "ko", layout: "cheonjiin", port: host)
        XCTAssertEqual(host.text, "가 ")
    }

    func testTypingOnlyReadsContextBeforeAndAfterActualWrites() {
        let host = Host("앞 문장 "), typing = KoreanTypingSession()
        typing.input("ㄱ", language: "ko", layout: "dubeolsik", port: host)
        host.reads = 0
        typing.input("ㅏ", language: "ko", layout: "dubeolsik", port: host)
        XCTAssertEqual(host.text, "앞 문장 가")
        XCTAssertLessThanOrEqual(host.reads, 3, "Each proxy read crosses the host boundary; reuse acknowledged snapshots")
    }

}
