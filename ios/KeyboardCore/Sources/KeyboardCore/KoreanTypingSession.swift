import Foundation

/// The extension's Korean input path; tests drive it through a fake port.
/// Native hosts can replace the owned marked composition in one operation.
/// Other ports keep the acknowledged minimal-write path. Space/return commit
/// the composition before inserting their own character, without rewriting it.
@MainActor public final class KoreanTypingSession {
    private var hangul = HangulComposer()
    private var cheonjiin = CheonjiinComposer()
    private var rendered = ""
    private var observed: DocumentContext?
    private var activeLayout = ""
    private var cycleKey = ""
    private var cycleIndex = 0
    private var cycleAt = Date.distantPast
    private var marked = false
    private var markedBefore = ""
    private var markedAfter = ""
    /// The host reflects writes late, so a read can still show text from before our last few keys.
    /// These are the before-cursor texts this session produced or was just shown, with the marked
    /// composition excluded. A read that matches one is our own lagging state, not a cursor move.
    private var ownDocument: UUID?
    private var ownAfter: String?
    private var expectedBefore: String?
    private var ownBefores: [String] = []
    public init() {}
    public var hasActiveComposition: Bool { !rendered.isEmpty }
    public var hasHostState: Bool { hasActiveComposition || ownDocument != nil }
    private func remember(_ before: String?) {
        guard let before else { return }
        if ownBefores.last.map({ !exact($0, before) }) ?? true { ownBefores.append(before) }
        if ownBefores.count > 8 { ownBefores.removeFirst(ownBefores.count - 8) }
    }
    private func expect(_ before: String, document: UUID, after: String) {
        expectedBefore = before; ownDocument = document; ownAfter = after; remember(before)
    }
    private func forget() { expectedBefore = nil; ownDocument = nil; ownAfter = nil; ownBefores = [] }
    /// After a cursor move, keyboard switch or dismissal the remembered states no longer describe the field.
    public func resetHostState() { forget() }
    /// Whether `context` is this session's own state as the host has reflected it so far.
    /// Never true for a read that already contains the marked text: that host committed it itself.
    public func recognizes(_ context: DocumentContext?) -> Bool {
        guard let context, let ownDocument, let ownAfter, context.documentID == ownDocument,
              context.selected?.isEmpty != false, exact(context.after ?? "", ownAfter) else { return false }
        let before = context.before ?? ""
        if marked, !rendered.isEmpty, exact(before, markedBefore + rendered) { return false }
        return ownBefores.contains { exact($0, before) }
    }

    public func finish(port: PartialEditPort? = nil) {
        if marked, let port {
            let current = port.read()
            // A remote proxy omits active marked text. Commit it only while its
            // anchor still matches; moving to another field/cursor must never reinsert it.
            // A host that sent and cleared the field drops the marked text with it: an empty field never gets it back.
            if port.hasText != false, let current, let observed, current.documentID == observed.documentID, current.selected?.isEmpty != false,
               (exact(current.before ?? "", markedBefore) && exact(current.after ?? "", markedAfter)) || recognizes(current) {
                port.commitMarkedComposition(rendered)
                expect(markedBefore + rendered, document: current.documentID, after: markedAfter)
            } else { port.endMarkedComposition(); forget() }
        }
        marked = false
        markedBefore = ""; markedAfter = ""
        hangul.reset(); cheonjiin.reset(); rendered = ""; observed = nil; cycleKey = ""
    }
    /// Abandon a composition whose host cleared it. Never commits cached text back into the field.
    public func discard(port: PartialEditPort? = nil) {
        if marked { port?.endMarkedComposition() }
        marked = false; markedBefore = ""; markedAfter = ""
        hangul.reset(); cheonjiin.reset(); rendered = ""; observed = nil; cycleKey = ""
        forget()
    }
    private func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    /// UITextDocumentProxy omits its marked text; UITextView includes it.
    /// Project only our current composition at its unchanged document/selection anchor.
    public func includingComposition(in context: DocumentContext?) -> DocumentContext? {
        guard marked, var context, let observed, context.documentID == observed.documentID,
              context.selected?.isEmpty != false, exact(context.before ?? "", markedBefore),
              exact(context.after ?? "", markedAfter) else { return context }
        context.before = markedBefore + rendered
        return context
    }
    private func synchronized(with current: DocumentContext?) -> Bool {
        guard var previous = observed, let current else { return false }
        previous.epoch = current.epoch // An epoch bump alone does not change the user's text.
        return previous == current
    }
    public func canContinueComposition(in context: DocumentContext?) -> Bool {
        synchronized(with: context) || recognizes(context)
    }
    public func input(_ value: String, language: String, layout: String, port: PartialEditPort, now: Date = Date()) {
        let jamo = value.count == 1 && value.first.map { "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".contains($0) } == true
        let moaki = layout == "moaki" && (jamo || (value.count == 2 && value.first.map { "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".contains($0) } == true && value.last.map { "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".contains($0) } == true))
        guard language == "ko", moaki || (layout == "dubeolsik" && jamo) || (layout == "cheonjiin" && (jamo || value == "ㆍ" || ["ㄱㅋㄲ", "ㄴㄹ", "ㄷㅌㄸ", "ㅂㅍㅃ", "ㅅㅎㅆ", "ㅇㅁ", "ㅈㅊㅉ"].contains(value))) else {
            finish(port: port); port.insert(value)
            if let before = expectedBefore { expectedBefore = before + value; remember(expectedBefore) }
            return
        }
        let current = port.read()
        if (!synchronized(with: current) && !recognizes(current)) || activeLayout != layout { finish(port: port) }
        activeLayout = layout
        if rendered.count >= 100 { finish(port: port) }
        if layout == "cheonjiin" {
            if ["ㅣ", "ㆍ", "ㅡ"].contains(value) {
                if now.timeIntervalSince(cycleAt) > 1 { cheonjiin.endCycle() }
                cheonjiin.primitive(value.first!); cycleKey = ""
            } else {
                let options = Array(value), cycle = cycleKey == value && now.timeIntervalSince(cycleAt) < 0.8
                cycleIndex = cycle ? (cycleIndex + 1) % options.count : 0
                cheonjiin.consonant(options[cycleIndex], replacePrevious: cycle); cycleKey = value
            }
            cycleAt = now; render(cheonjiin.text, context: current, port: port)
        } else { for stroke in value { hangul.append(stroke) }; render(hangul.text, context: current, port: port) }
    }
    public func delete(port: PartialEditPort) {
        let current = port.read()
        guard synchronized(with: current) || recognizes(current), !rendered.isEmpty else { deleteCommitted(port); return }
        if activeLayout == "cheonjiin", cheonjiin.delete() { render(cheonjiin.text, context: current, port: port) }
        else if hangul.delete() { render(hangul.text, context: current, port: port) }
        else { deleteCommitted(port) }
    }
    private func deleteCommitted(_ port: PartialEditPort) {
        finish(port: port); port.deleteBackward()
        if let before = expectedBefore {
            if before.isEmpty { forget() } else { expectedBefore = String(before.dropLast()); remember(expectedBefore) }
        }
    }
    private func render(_ text: String, context: DocumentContext?, port: PartialEditPort) {
        if port.supportsMarkedComposition, let context, context.selected?.isEmpty != false,
           rendered.isEmpty || marked {
            if ownDocument != nil, ownDocument != context.documentID { forget() }
            let own = recognizes(context)
            let before = context.before ?? ""
            let prefix = marked ? markedBefore : (own ? expectedBefore ?? before : before)
            guard !marked || own || exact(before, prefix) || ContextMatch.knownSuffix(prefix + rendered, in: before) else { finish(port: port); return }
            if !own { remember(before) }
            markedBefore = prefix; markedAfter = context.after ?? ""
            marked = true
            expect(prefix, document: context.documentID, after: markedAfter)
            port.setMarkedComposition(text)
            observed = port.read()
            guard let current = observed, current.documentID == context.documentID, current.epoch == context.epoch,
                  current.selected?.isEmpty != false, exact(current.after ?? "", context.after ?? ""),
                  exact(current.before ?? "", prefix) || ContextMatch.knownSuffix(prefix + text, in: current.before) || recognizes(current) else {
                finish(port: port); return
            }
            rendered = text
            if text.isEmpty { finish(port: port) }
            return
        }
        if rendered.isEmpty {
            port.insert(text); observed = port.read()
        } else {
            let old = Array(rendered), new = Array(text)
            var common = 0
            while common < min(old.count, new.count), old[common] == new[common] { common += 1 }
            let removed = String(old[common...]), replacement = String(new[common...])
            // Only the changing syllable(s) belonging to this session may be replaced.
            guard removed.count <= 2, let context, let before = context.before,
                  context.selected?.isEmpty != false, ContextMatch.knownSuffix(rendered, in: before) else { finish(); return }
            let prefix = String(before.dropLast(rendered.count)) + String(old[..<common])
            func acknowledged(_ suffix: String) -> Bool {
                observed = port.read()
                guard let current = observed, current.documentID == context.documentID, current.epoch == context.epoch,
                      current.selected?.isEmpty != false, current.after == context.after else { return false }
                let expected = prefix + suffix
                // A proxy may return nil for the empty beginning/end of a document.
                return expected.isEmpty ? (current.before ?? "").isEmpty : ContextMatch.knownSuffix(expected, in: current.before)
            }
            var remaining = removed
            while !remaining.isEmpty {
                port.deleteBackward(); remaining.removeLast()
                guard acknowledged(remaining) else { finish(); return }
            }
            if !replacement.isEmpty {
                port.insert(replacement)
                guard acknowledged(replacement) else { finish(); return }
            }
        }
        rendered = text
        if text.isEmpty { finish() }
    }
}
