import Foundation

/// A remote keyboard proxy can briefly report an empty field while its marked text is still present.
/// Only that ambiguous state waits; ordinary keys run synchronously without reading text here.
@MainActor public final class KeyboardHostInputGate {
    public enum Event: Equatable, Sendable {
        case input(String, language: String, layout: String)
        /// Search/send/go submits the field; it does not append a newline to the composing context.
        case returnAction
        case delete
        case deleteWord
    }
    public enum Outcome: Equatable {
        case applied
        case waiting
        case cleared(replayed: [Event])
        case abandoned
    }
    public static let confirmationInterval: TimeInterval = 0.1
    private let typing: KoreanTypingSession
    private var emptySince: TimeInterval?
    private var document: UUID?
    private struct QueuedEvent { let event: Event; let inputTime: Date }
    private var events: [QueuedEvent] = []
    public var isWaiting: Bool { emptySince != nil }
    public var hasPendingEvents: Bool { !events.isEmpty }
    public init(typing: KoreanTypingSession) { self.typing = typing }

    public func cancel() { emptySince = nil; document = nil; events = [] }

    public func submit(_ event: Event, port: PartialEditPort, now: TimeInterval, inputTime: Date = Date()) -> Outcome {
        if !isWaiting, !typing.hasHostState || port.hasText != false {
            perform(event, port: port, inputTime: inputTime)
            return .applied
        }
        events.append(QueuedEvent(event: event, inputTime: inputTime))
        return observe(port: port, now: now)
    }

    public func observe(port: PartialEditPort, now: TimeInterval) -> Outcome {
        guard isWaiting || typing.hasHostState else { return .applied }
        if !isWaiting, port.hasText != false { return .applied }
        guard let current = port.read() else {
            cancel(); typing.discard()
            return .abandoned
        }
        if let document, current.documentID != document {
            // Queued keys belong to the original field, never the newly focused one.
            cancel(); typing.discard()
            return .abandoned
        }
        let empty = port.hasText == false && (current.before ?? "").isEmpty &&
            current.selected?.isEmpty != false && (current.after ?? "").isEmpty
        if !empty {
            if isWaiting, !typing.canContinueComposition(in: current) {
                // An external edit or cursor move ended the old target even within the same document.
                cancel(); typing.discard()
                return .abandoned
            }
            let replay = events
            cancel()
            for event in replay { perform(event.event, port: port, inputTime: event.inputTime) }
            return .applied
        }
        if let emptySince, now - emptySince >= Self.confirmationInterval {
            let replay = events
            cancel()
            typing.discard(port: port)
            for event in replay { perform(event.event, port: port, inputTime: event.inputTime) }
            return .cleared(replayed: replay.map(\.event))
        }
        if emptySince == nil { emptySince = now; document = current.documentID }
        return .waiting
    }

    private func perform(_ event: Event, port: PartialEditPort, inputTime: Date) {
        switch event {
        case let .input(value, language, layout): typing.input(value, language: language, layout: layout, port: port, now: inputTime)
        case .returnAction: typing.finish(port: port); port.insert("\n")
        case .delete: typing.delete(port: port)
        case .deleteWord:
            let word = DeleteRepeat.lastWord(in: typing.includingComposition(in: port.read())?.before ?? "")
            typing.finish(port: port); typing.resetHostState()
            for _ in word { port.deleteBackward() }
        }
    }
}
