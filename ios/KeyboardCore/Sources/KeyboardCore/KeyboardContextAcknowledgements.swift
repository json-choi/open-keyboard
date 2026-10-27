import Foundation

/// Recognizes short-lived notifications from our own already-observed writes.
/// This never authorizes an edit: typing still verifies the live port.
public struct KeyboardContextAcknowledgements {
    private struct Entry { let context: DocumentContext; let at: TimeInterval }
    private var entries: [Entry] = []
    private let maximumAge: TimeInterval
    private let capacity: Int
    public init(maximumAge: TimeInterval = 0.12, capacity: Int = 16) {
        precondition(maximumAge > 0 && capacity > 0)
        self.maximumAge = maximumAge; self.capacity = capacity
    }
    public mutating func reset() { entries.removeAll() }
    public mutating func record(_ context: DocumentContext?, now: TimeInterval) {
        entries.removeAll { now - $0.at >= maximumAge }
        guard let context else { return }
        if entries.count == capacity { entries.removeFirst() }
        entries.append(Entry(context: context, at: now))
    }
    public mutating func contains(_ context: DocumentContext?, now: TimeInterval) -> Bool {
        entries.removeAll { now - $0.at >= maximumAge }
        guard let context else { return false }
        return entries.contains { entry in
            var expected = entry.context; expected.epoch = context.epoch
            return expected == context
        }
    }
}
