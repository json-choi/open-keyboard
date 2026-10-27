import Foundation

/// Decides when a key plays haptic/sound feedback: once on touch-down and never again when that
/// press commits its input. Overlapping fast presses each keep a silent commit; a single timestamp
/// used to forget the earlier press and fire a second, late haptic on release.
public struct KeyFeedbackLedger: Sendable {
    /// Touch-downs closer than this arrive in one touch event and share a single haptic.
    public static let simultaneous: TimeInterval = 0.008
    /// A press cancelled without input stops counting once typing pauses this long.
    public static let lapse: TimeInterval = 1.5
    private var pending = 0
    private var lastPress: TimeInterval = -.infinity
    public init() {}
    /// True when this touch-down should play feedback.
    public mutating func press(at time: TimeInterval) -> Bool {
        let play = time - lastPress > Self.simultaneous
        pending += 1; lastPress = time
        return play
    }
    /// True when this input had no feedback-giving press of its own, such as a repeated delete.
    public mutating func input(at time: TimeInterval) -> Bool {
        if time - lastPress > Self.lapse { pending = 0 }
        if pending > 0 { pending -= 1; return false }
        return true
    }
    public mutating func reset() { pending = 0; lastPress = -.infinity }
}
