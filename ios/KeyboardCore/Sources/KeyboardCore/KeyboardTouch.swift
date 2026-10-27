/// Explicit calibration in fractions of a row's key height. Neutral until measured.
public struct KeyboardTouchCorrection: Sendable {
    public let verticalOffset: Double
    public let radiusScale: Double
    public init(verticalOffset: Double = 0, radiusScale: Double = 1) {
        self.verticalOffset = verticalOffset.isFinite ? min(0.25, max(-0.25, verticalOffset)) : 0
        self.radiusScale = radiusScale.isFinite ? min(1.5, max(0.75, radiusScale)) : 1
    }
}

/// Local key geometry only. Candidates never replace the user's chosen key automatically.
public struct KeyboardTouchTarget: Sendable {
    public let id: Int
    public let x: Double, y: Double, width: Double, height: Double
    public let group: Int, row: Int
    public let correctable: Bool
    public init(id: Int, x: Double, y: Double, width: Double, height: Double, group: Int = 1, row: Int = 0, correctable: Bool? = nil) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.height = height
        self.group = group; self.row = row
        self.correctable = correctable ?? (group == 1)
    }
    private var valid: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0 }
    private func correctedY(_ corrections: [Int: KeyboardTouchCorrection]) -> Double {
        // Space and command keys keep their physical position.
        y + (correctable ? (corrections[row]?.verticalOffset ?? 0) * height : 0)
    }
    private func distance(_ px: Double, _ py: Double, corrections: [Int: KeyboardTouchCorrection]) -> Double {
        let top = correctedY(corrections)
        let dx = max(x - px, 0, px - x - width), dy = max(top - py, 0, py - top - height)
        return dx * dx + dy * dy
    }
    /// Distance to the key's edge in its own widths and heights: positive outside, negative inside
    /// (how deep the touch is). Equal-sized neighbours meet exactly where they are drawn. Heights count
    /// at `verticalReach`, since taps scatter less up and down than sideways relative to key size.
    private func depth(_ px: Double, _ py: Double, corrections: [Int: KeyboardTouchCorrection]) -> Double {
        let top = correctedY(corrections), tall = height * Self.verticalReach
        let dx = max(x - px, 0, px - x - width) / width, dy = max(top - py, 0, py - top - height) / tall
        if dx > 0 || dy > 0 { return (dx * dx + dy * dy).squareRoot() }
        return -min(min(px - x, x + width - px) / width, min(py - top, top + height - py) / tall)
    }
    private func centerDistance(_ px: Double, _ py: Double, corrections: [Int: KeyboardTouchCorrection]) -> Double {
        let dx = (px - x - width / 2) / width, dy = (py - correctedY(corrections) - height / 2) / height
        return dx * dx + dy * dy
    }
    private func radius(_ corrections: [Int: KeyboardTouchCorrection], unit: Double) -> Double {
        max(8 * unit, min(width, height) * 0.35 * (correctable ? corrections[row]?.radiusScale ?? 1 : 1))
    }
    /// Most of a key's own width or height that a predicted neighbour may take, so the middle half of
    /// every key always types that key (Gunawardana et al.'s anchored key-target resizing).
    public static let maxReach = 0.25
    /// Vertical reach relative to sideways reach: σy ≈ 0.20 H against σx ≈ 0.32 W (Adhikary 2023).
    public static let verticalReach = 0.5
    private static func insideEnvelope(x: Double, y: Double, targets: [Self], margin: Double) -> Bool {
        guard x.isFinite, y.isFinite, margin.isFinite, margin >= 0 else { return false }
        var left = Double.infinity, top = Double.infinity, right = -Double.infinity, bottom = -Double.infinity
        for key in targets where key.valid {
            left = min(left, key.x); top = min(top, key.y)
            right = max(right, key.x + key.width); bottom = max(bottom, key.y + key.height)
        }
        return x >= left - margin && x <= right + margin && y >= top - margin && y <= bottom + margin
    }
    /// Size-aware retention and centre tie-breaking. The hot move path does not allocate candidates.
    /// `reach` is each predicted key's share of its own width (0…`maxReach`) that it takes from a
    /// neighbour with less reach, sideways, and half that share of its height up and down.
    /// Keys missing from a non-empty `reach` (controls, digits) keep everything inside their drawn frame.
    public static func resolve(x: Double, y: Double, targets: [Self], current: Int? = nil, group: Int? = nil, hysteresis: Double? = nil, outerMargin: Double = 8, unit: Double = 1, corrections: [Int: KeyboardTouchCorrection] = [:], reach: [Int: Double] = [:]) -> Int? {
        guard unit.isFinite, unit > 0, insideEnvelope(x: x, y: y, targets: targets, margin: outerMargin) else { return nil }
        if !corrections.isEmpty || !reach.isEmpty, let fixed = targets.first(where: { $0.valid && (!$0.correctable || !reach.isEmpty && reach[$0.id] == nil) && $0.distance(x, y, corrections: [:]) == 0 }) {
            return group == nil || fixed.group == group ? fixed.id : nil
        }
        // Past the keyboard's outer edge, keys compete as if the touch were on that edge, so reach
        // never carries a key sideways along the margin over its neighbour.
        var px = x, py = y
        if !reach.isEmpty {
            var left = Double.infinity, top = Double.infinity, right = -Double.infinity, bottom = -Double.infinity
            for key in targets where key.valid { left = min(left, key.x); top = min(top, key.y); right = max(right, key.x + key.width); bottom = max(bottom, key.y + key.height) }
            px = min(max(x, left), right); py = min(max(y, top), bottom)
        }
        var nearest: Self?, cost = Double.infinity, center = Double.infinity, grown = 0.0, retained: Int?
        for key in targets where key.valid {
            let share = min(maxReach, max(0, reach[key.id].flatMap { $0.isFinite ? $0 : nil } ?? 0))
            // Two keys trade the strip between them by the difference of their reach.
            let value = key.depth(px, py, corrections: corrections) - 2 * share
            let middle = key.centerDistance(px, py, corrections: corrections)
            if key.id == current, group == nil || key.group == group {
                let margin = hysteresis ?? min(8 * unit, max(4 * unit, min(key.width, key.height) * 0.14))
                if margin.isFinite && margin >= 0 && key.distance(x, y, corrections: corrections) <= margin * margin { retained = key.id }
            }
            if value < cost || (value == cost && (middle < center || (middle == center && key.id < (nearest?.id ?? Int.max)))) {
                nearest = key; cost = value; center = middle; grown = share
            }
        }
        if let retained { return retained }
        guard let key = nearest else { return nil }
        let radius = key.radius(corrections, unit: unit) + grown * max(key.width, key.height)
        if (group == nil || key.group == group) && key.distance(x, y, corrections: corrections) <= radius * radius { return key.id }
        // Prediction may change which key a touch types, never whether it types one.
        return reach.isEmpty ? nil : resolve(x: x, y: y, targets: targets, current: current, group: group, hysteresis: hysteresis, outerMargin: outerMargin, unit: unit, corrections: corrections)
    }
    /// Tracking for a finger that already owns a key. A short drift onto a control, a gap or past
    /// the keyboard edge keeps that key instead of silently dropping the tap; only a deliberate
    /// slide (beyond `releaseSlack`) leaves it. Sliding onto another letter still switches keys.
    /// `reach` is the one in effect when the finger went down, so lifting it keeps the predicted key.
    public static func follow(x: Double, y: Double, targets: [Self], current: Int?, group: Int? = nil, releaseSlack: Double = 20, outerMargin: Double = 8, unit: Double = 1, corrections: [Int: KeyboardTouchCorrection] = [:], reach: [Int: Double] = [:]) -> Int? {
        if let id = resolve(x: x, y: y, targets: targets, current: current, group: group, outerMargin: outerMargin, unit: unit, corrections: corrections, reach: reach) { return id }
        guard let current, x.isFinite, y.isFinite, unit.isFinite, unit > 0,
              let key = targets.first(where: { $0.id == current && $0.valid && (group == nil || $0.group == group) }) else { return nil }
        let slack = releaseSlack * unit
        return slack.isFinite && slack >= 0 && key.distance(x, y, corrections: corrections) <= slack * slack ? current : nil
    }
    /// Nearby alternatives for boundary diagnostics and future local composition; no text is stored.
    public static func candidates(x: Double, y: Double, targets: [Self], group: Int? = nil, limit: Int = 3, outerMargin: Double = 8, unit: Double = 1, corrections: [Int: KeyboardTouchCorrection] = [:]) -> [Int] {
        guard limit > 0, unit.isFinite, unit > 0, insideEnvelope(x: x, y: y, targets: targets, margin: outerMargin) else { return [] }
        if !corrections.isEmpty, let control = targets.first(where: { $0.valid && !$0.correctable && $0.distance(x, y, corrections: [:]) == 0 }) {
            return group == nil || control.group == group ? [control.id] : []
        }
        return targets.filter { key in
            guard key.valid, group == nil || key.group == group else { return false }
            let radius = key.radius(corrections, unit: unit)
            return key.distance(x, y, corrections: corrections) <= radius * radius
        }.sorted { a, b in
            let first = a.distance(x, y, corrections: corrections), second = b.distance(x, y, corrections: corrections)
            if first != second { return first < second }
            let ac = a.centerDistance(x, y, corrections: corrections), bc = b.centerDistance(x, y, corrections: corrections)
            return ac != bc ? ac < bc : a.id < b.id
        }.prefix(min(limit, targets.count)).map(\.id)
    }
}

public struct KeyboardTouchSequence: Sendable {
    public struct Commit: Equatable, Sendable {
        public let pointer: Int, key: Int
    }
    private struct Press: Sendable { let pointer: Int; var key: Int? }
    private var presses: [Press] = []
    public init() {}
    public var pressedKeys: [Int] { presses.compactMap(\.key) }
    public func contains(_ pointer: Int) -> Bool { presses.contains { $0.pointer == pointer } }
    public mutating func begin(_ pointer: Int, key: Int?) {
        cancel(pointer); presses.append(Press(pointer: pointer, key: key))
    }
    public mutating func move(_ pointer: Int, key: Int?) {
        guard let index = presses.firstIndex(where: { $0.pointer == pointer }) else { return }
        presses[index].key = key
    }
    /// When fingers overlap, commit older presses first and ignore their later physical release.
    public mutating func end(_ pointer: Int) -> [Commit] {
        guard let index = presses.firstIndex(where: { $0.pointer == pointer }) else { return [] }
        let ready = presses.prefix(index + 1).compactMap { press in press.key.map { Commit(pointer: press.pointer, key: $0) } }
        presses.removeFirst(index + 1); return ready
    }
    public mutating func cancel(_ pointer: Int) { presses.removeAll { $0.pointer == pointer } }
    public mutating func flush() -> [Commit] {
        let ready = presses.compactMap { press in press.key.map { Commit(pointer: press.pointer, key: $0) } }
        presses.removeAll(); return ready
    }
    public mutating func cancelAll() { presses.removeAll() }
}

/// Space becomes a cursor gesture only after a deliberate hold and horizontal move.
/// Incremental detents prevent boundary jitter from moving the cursor back and forth.
public struct KeyboardCursorGesture: Sendable {
    public private(set) var active = false
    private var position = 0.0
    public init() {}
    public mutating func update(dx: Double, dy: Double, elapsedMilliseconds: Double, activationDistance: Double = 18, step: Double = 12) -> Int {
        guard step > 0 else { return 0 }
        if !active {
            guard elapsedMilliseconds >= 280, abs(dx) >= activationDistance, abs(dx) > abs(dy) * 1.2 else { return 0 }
            active = true; position = dx < 0 ? -activationDistance : activationDistance
        }
        let delta = Int((dx - position) / step)
        position += Double(delta) * step
        return delta
    }
}
