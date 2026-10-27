import Foundation

/// One read of the host field. Equality compares bytes so NFC/NFD host changes are visible.
public struct DocumentContext: Equatable, Sendable {
    public var documentID: UUID
    public var epoch: UInt64
    public var before: String?
    public var selected: String?
    public var after: String?
    public init(documentID: UUID, epoch: UInt64, before: String?, selected: String?, after: String?) {
        self.documentID = documentID; self.epoch = epoch; self.before = before; self.selected = selected; self.after = after
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        func exact(_ a: String?, _ b: String?) -> Bool {
            switch (a, b) { case (nil, nil): return true; case (let a?, let b?): return a.utf8.elementsEqual(b.utf8); default: return false }
        }
        return lhs.documentID == rhs.documentID && lhs.epoch == rhs.epoch && exact(lhs.before, rhs.before) && exact(lhs.selected, rhs.selected) && exact(lhs.after, rhs.after)
    }
}

public enum ContextMatch {
    /// An expected empty slice must be observed empty: every string hasSuffix("")
    /// would incorrectly acknowledge a failed final deletion. Compare bytes for
    /// nonempty slices so NFC/NFD host changes cannot impersonate the snapshot.
    public static func knownSuffix(_ expected: String, in observed: String?) -> Bool {
        guard let observed else { return false }
        if expected.isEmpty { return observed.isEmpty }
        return observed.utf8.suffix(expected.utf8.count).elementsEqual(expected.utf8)
    }
}

/// The host text field as the typing session sees it: UITextDocumentProxy in the extension, a fake in tests.
@MainActor public protocol PartialEditPort {
    var supportsMarkedComposition: Bool { get }
    func setMarkedComposition(_ text: String)
    func commitMarkedComposition(_ text: String)
    func endMarkedComposition()
    /// Advisory text presence, marked text included; remote values may lag. Nil when unavailable.
    var hasText: Bool? { get }
    func read() -> DocumentContext?
    func deleteBackward()
    func insert(_ text: String)
}

public extension PartialEditPort {
    var supportsMarkedComposition: Bool { false }
    func setMarkedComposition(_ text: String) {}
    func commitMarkedComposition(_ text: String) {}
    func endMarkedComposition() {}
    var hasText: Bool? { nil }
}
