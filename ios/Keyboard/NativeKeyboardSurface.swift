import UIKit
import UIKit.UIGestureRecognizerSubclass
import KeyboardCore

/// The extension leaves the system's input-mode and dictation dock to UIKit.
@MainActor class NativeKeyboardInputController: UIInputViewController {
    let surface = NativeKeyboardSurface()
    private var keyboardHeight: NSLayoutConstraint?
    private var language = "ko"
    private var layout = "dubeolsik"
    private var preferredKeyHeight: CGFloat = 44
    private var fittedWidth: CGFloat = 0
    private var fittedCompact = false
    var onNextInputMode: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        // UIInputView supplies the system material and rounded keyboard outline, including its dock.
        // An opaque fill here paints a rectangle over that material while the dock stays translucent.
        view.backgroundColor = .clear
        view.isOpaque = false
        (view as? UIInputView)?.allowsSelfSizing = true
        view.tintColor = Palette.accent
        surface.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        surface.onNextKeyboard = { [weak self] in
            guard let self else { return }
            if let onNextInputMode { onNextInputMode() } else { advanceToNextInputMode() }
        }
        keyboardHeight = view.heightAnchor.constraint(equalToConstant: 266)
        keyboardHeight?.priority = .init(999); keyboardHeight?.isActive = true
    }
    func configure(language: String, layout: String, keyHeight: CGFloat) {
        loadViewIfNeeded()
        self.language = language; self.layout = layout; preferredKeyHeight = keyHeight
        fitKeyboard()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        surface.prepareForPresentation(); fitKeyboard()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); fitKeyboard()
        // The host window's system-edge recognizers hold back touchesBegan for keys near the
        // screen edges and bottom row; a fast tap there could arrive late or be swallowed.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        keyboardHeight?.constant = surface.contentHeight + view.safeAreaInsets.bottom
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let compact = view.window?.windowScene?.interfaceOrientation.isLandscape == true
        let height = surface.contentHeight + view.safeAreaInsets.bottom
        if view.bounds.width != fittedWidth || compact != fittedCompact || keyboardHeight?.constant != height { fitKeyboard() }
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.fitKeyboard() }
    }
    private func fitKeyboard() {
        fittedWidth = view.bounds.width
        let compact = view.window?.windowScene?.interfaceOrientation.isLandscape == true
        fittedCompact = compact
        surface.configure(language: language, layout: layout, height: compact ? min(preferredKeyHeight, 32) : preferredKeyHeight, needsNext: needsInputModeSwitchKey, compact: compact)
        keyboardHeight?.constant = surface.contentHeight + view.safeAreaInsets.bottom
    }
}

/// Visual gaps belong to the nearest key's touch target, including touch-up tracking.
@MainActor private final class KeyboardKeyButton: UIButton {
    var restingColor: UIColor?
    var pressedColor: UIColor?
    override var isHighlighted: Bool {
        didSet { UIView.performWithoutAnimation { backgroundColor = isHighlighted ? pressedColor : restingColor } }
    }
    var touchGroup = 0
    var inputValue = ""
    var containsTouch: ((CGPoint) -> Bool)?
    var numberHint: String? {
        didSet {
            numberLabel.text = numberHint
            if numberLabel.superview == nil {
                numberLabel.translatesAutoresizingMaskIntoConstraints = false; addSubview(numberLabel)
                numberLabel.font = .systemFont(ofSize: 10); numberLabel.textColor = Palette.secondary
                numberLabel.isUserInteractionEnabled = false
                NSLayoutConstraint.activate([numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3), numberLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)])
            }
        }
    }
    private let numberLabel = UILabel()
    private var moakiBegan: TimeInterval = 0
    private var moakiMoved = false
    var moakiBase: String?
    var onMoakiInput: ((String) -> Void)?
    var onMoakiPreview: ((String?) -> Void)?
    private var stroke = MoakiGesture()
    private var strokeThreshold = 12.0
    private var origin = CGPoint.zero
    private var trackingMoaki = false
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard moakiBase != nil else { return super.beginTracking(touch, with: event) }
        strokeThreshold = MoakiGesture.activationDistance(keyWidth: bounds.width, keyHeight: bounds.height)
        origin = touch.location(in: self); stroke = MoakiGesture(threshold: strokeThreshold); trackingMoaki = true; isHighlighted = true
        moakiBegan = touch.timestamp; moakiMoved = false
        preview(); return true
    }
    private func advance(_ touch: UITouch) {
        let point = touch.location(in: self)
        if hypot(point.x - origin.x, point.y - origin.y) >= strokeThreshold { moakiMoved = true }
        stroke.move(x: Double(point.x - origin.x), y: Double(point.y - origin.y)); preview()
    }
    private func preview() {
        guard let base = moakiBase else { return }
        guard let input = stroke.input(base: base) else { onMoakiPreview?("—"); return }
        var composer = HangulComposer(); for jamo in input { composer.append(jamo) }
        onMoakiPreview?(composer.text)
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard trackingMoaki else { return super.continueTracking(touch, with: event) }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] { advance(sample) }; return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard trackingMoaki, let base = moakiBase else { super.endTracking(touch, with: event); return }
        if let touch { for sample in event?.coalescedTouches(for: touch) ?? [touch] { advance(sample) } }
        trackingMoaki = false; isHighlighted = false; onMoakiPreview?(nil)
        if let numberHint, !moakiMoved, let touch, touch.timestamp - moakiBegan >= 0.45 { onMoakiInput?(numberHint) }
        else if let input = stroke.input(base: base) { onMoakiInput?(input) }
    }
    override func cancelTracking(with event: UIEvent?) {
        trackingMoaki = false; isHighlighted = false; onMoakiPreview?(nil); super.cancelTracking(with: event)
    }
    override func accessibilityActivate() -> Bool {
        guard let base = moakiBase else { return super.accessibilityActivate() }
        onMoakiInput?(base.isEmpty ? "ㅣ" : base); return true
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Once this key owns a touch, a short lift-off drift onto a neighbour still counts as
        // inside, so `.touchUpInside` fires instead of a silent `.touchUpOutside`.
        if isTracking, bounds.insetBy(dx: -Self.releaseSlack, dy: -Self.releaseSlack).contains(point) { return true }
        return containsTouch?(point) ?? super.point(inside: point, with: event)
    }
    /// Lift-off drift (pt) that still belongs to the pressed key.
    static let releaseSlack: CGFloat = 20
}

/// Receives every touch on the key surface at once. A keyboard extension's window holds back
/// `touchesBegan` near the screen's side and bottom edges (system gesture gates) by up to a second,
/// which reordered or lost fast taps on ㅂ, ㅁ, ㅔ and ㅣ; gesture recognizers are not held back.
/// It never cancels or blocks the views and recognizers it watches.
@MainActor private final class KeyboardTouchRecognizer: UIGestureRecognizer {
    var onBegan: ((Set<UITouch>) -> Void)?
    var onMoved: ((Set<UITouch>) -> Void)?
    var onEnded: ((Set<UITouch>) -> Void)?
    var onCancelled: ((Set<UITouch>) -> Void)?
    private var active = Set<ObjectIdentifier>()
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        active.formUnion(touches.map(ObjectIdentifier.init)); onBegan?(touches)
        state = state == .possible ? .began : .changed
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { onMoved?(touches); state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        active.subtract(touches.map(ObjectIdentifier.init)); onEnded?(touches)
        state = active.isEmpty ? .ended : .changed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        active.subtract(touches.map(ObjectIdentifier.init)); onCancelled?(touches)
        state = active.isEmpty ? .cancelled : .changed
    }
    override func reset() { super.reset(); active.removeAll() }
}

/// The extension's key surface: tool strip, key rows, emoji panel and text lists.
@MainActor final class NativeKeyboardSurface: UIView {
    let tools = KeyboardToolStrip()
    private let list = KeyboardTextList()
    var onLanguageChange: ((String) -> Void)?
    private func switchLanguage() {
        language = language == "ko" ? "en" : "ko"; symbols = 0
        onLanguageChange?(language); refresh()
    }
    /// Saved phrases or the clipboard list replace the key rows until the user goes back.
    private var listVisible = false
    var onListInput: ((String) -> Void)?
    var onClearClipboard: (() -> Void)?
    /// Called before the clipboard list opens, so it shows what was copied while the keyboard was hidden.
    var onOpenClipboard: (() -> [String])?
    var snippets: [String] = []
    private func showSnippets() {
        list.show(title: L("자주 쓰는 문구"), items: snippets, empty: L("앱의 설정에서 문구를 추가하세요."), clearable: false)
        setListVisible(true)
    }
    private func showClipboard() {
        let items = onOpenClipboard?() ?? []
        list.show(title: L("클립보드"), items: items, empty: L("복사한 텍스트가 여기에 표시돼요."), clearable: !items.isEmpty)
        setListVisible(true)
    }
    /// UIKit may rehost an existing input view after focus or window changes.
    /// Restore all visibility flags together instead of relying on a mode toggle
    /// whose early-return can leave an old hidden stack in a new presentation.
    func prepareForPresentation() {
        cancelTaps(); moakiPreview.removeFromSuperview()
        repeatTimer?.invalidate(); repeatTimer = nil
        listVisible = false; emojiVisible = false
        rows.isHidden = false; tools.isHidden = false; list.isHidden = true
        toolsHeight.isActive = true; stack.isHidden = false; emojiPanel.isHidden = true
        if rows.arrangedSubviews.isEmpty { refresh() }
        setNeedsLayout()
    }
    private func setListVisible(_ visible: Bool) {
        guard visible != listVisible else { return }
        cancelTaps()
        moakiPreview.removeFromSuperview()
        if visible { emojiVisible = false }
        listVisible = visible; rows.isHidden = visible; tools.isHidden = visible
        toolsHeight.isActive = !visible; list.isHidden = !visible
        stack.isHidden = emojiVisible; emojiPanel.isHidden = !emojiVisible
        repeatTimer?.invalidate(); repeatTimer = nil
        setNeedsLayout()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
    var onInput: ((String) -> Void)?
    /// Touch-down on any key, so haptics and click sound don't wait for the finger to lift.
    var onPress: (() -> Void)?
    var onDelete: (() -> Void)?
    /// A held delete past 3 seconds removes a word per repeat.
    var onDeleteWord: (() -> Void)?
    /// Sliding left from delete: the number of characters the slide has removed so far, live.
    var onDeleteSlide: ((Int) -> Void)?
    var onDeleteSlideEnd: (() -> Void)?
    var onNextKeyboard: (() -> Void)?
    var onCursor: ((Int) -> Void)?
    private let stack = UIStackView()
    private let rows = UIStackView()
    private let emojiPanel = NativeEmojiPanel()
    private var emojiBottomInset: NSLayoutConstraint!
    private var emojiVisible = false
    private var language = "ko"
    private var layout = "dubeolsik"
    private var symbols = 0
    private var shifted = false
    private var shiftHeld = false
    private var shiftUsed = false
    private var shiftBeforePress = false
    private var needsNext = false
    private var keyHeight: CGFloat = 44
    private var compact = false
    private var toolsHeight: NSLayoutConstraint!
    private var bottomInset: NSLayoutConstraint!
    /// iOS already leaves about 17pt of its own below a third-party keyboard (Apple's keyboard puts its
    /// space row there), so in portrait the bottom row sits on the view's edge, level with the system one.
    private static let bottomGap: CGFloat = 0
    private var renderedKeyHeight: CGFloat {
        // Four symbol rows occupy the same area as five Korean rows.
        language == "ko" && ["cheonjiin", "moaki"].contains(layout) && symbols > 0 ? (5 * keyHeight + rows.spacing) / 4 : keyHeight
    }
    var contentHeight: CGFloat {
        let count: CGFloat = language == "ko" && ["cheonjiin", "moaki"].contains(layout) ? 5 : 4
        return (compact ? 32 + 4 + 6 : 44 + 8 + Self.bottomGap) + count * keyHeight + (count - 1) * rows.spacing
    }
    private var touchKeys: [KeyboardKeyButton] = []
    private var touchTargets: [KeyboardTouchTarget] = []
    private var touchSequence = KeyboardTouchSequence()
    private struct Tap {
        let pointer: Int, initialKey: Int, origin: CGPoint, began: TimeInterval
        /// Predicted reach at touch-down, kept for the rest of this finger's press.
        var reach: [Int: Double] = [:]
        var key: Int?
        var cursor = KeyboardCursorGesture()
    }
    private var taps: [ObjectIdentifier: Tap] = [:]
    private var nextPointer = 0
    private var touchSize = CGSize.zero
    private var touchGeometryDirty = true
    private var letterKeys: [KeyboardKeyButton] = []
    private weak var shiftKey: KeyboardKeyButton?
    private var repeatTimer: Timer?
    private var repeatStarted: TimeInterval = 0
    private var repeats = 0
    private var tapPrediction = KoreanTapPrediction()
    private weak var enterKey: KeyboardKeyButton?
    private struct ReturnKeyStyle: Equatable { var title: String?; var enabled = true }
    private var returnKeyStyle = ReturnKeyStyle()
    private let moakiPreview = UILabel()
    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }
    private var keyColor: UIColor { Palette.key }
    private var specialColor: UIColor { Palette.specialKey }
    override init(frame: CGRect) {
        super.init(frame: frame)
        tools.onSnippets = { [weak self] in self?.showSnippets() }
        tools.onClipboard = { [weak self] in self?.showClipboard() }
        list.onSelect = { [weak self] value in self?.setListVisible(false); self?.onListInput?(value) }
        list.onClear = { [weak self] in self?.onClearClipboard?(); self?.setListVisible(false) }
        isMultipleTouchEnabled = true
        // A keyboard extension gets no touches where its view is fully transparent, which left the
        // gaps between keys and the edge insets dead on devices. Keep them barely, invisibly opaque.
        backgroundColor = UIColor(white: 0, alpha: 0.001)
        isOpaque = false
        let recognizer = KeyboardTouchRecognizer()
        recognizer.onBegan = { [weak self] in self?.beginTaps($0) }
        recognizer.onMoved = { [weak self] in self?.moveTaps($0) }
        recognizer.onEnded = { [weak self] in self?.endTaps($0) }
        recognizer.onCancelled = { [weak self] in self?.cancelTaps($0) }
        addGestureRecognizer(recognizer)
        tintColor = Palette.accent
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack); stack.addArrangedSubview(tools); stack.addArrangedSubview(rows); stack.addArrangedSubview(list); list.isHidden = true
        emojiPanel.translatesAutoresizingMaskIntoConstraints = false; addSubview(emojiPanel); emojiPanel.isHidden = true
        emojiBottomInset = emojiPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        NSLayoutConstraint.activate([emojiPanel.topAnchor.constraint(equalTo: topAnchor), emojiPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), emojiPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), emojiBottomInset])
        emojiPanel.onInput = { [weak self] value in self?.tapPrediction.reset(); self?.onInput?(value) }
        emojiPanel.onDelete = { [weak self] in self?.onDelete?() }
        emojiPanel.onBack = { [weak self] in self?.setEmojiVisible(false) }
        list.onBack = { [weak self] in self?.setListVisible(false) }
        rows.axis = .vertical; rows.spacing = 10
        toolsHeight = tools.heightAnchor.constraint(equalToConstant: 44)
        bottomInset = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomGap)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), bottomInset, stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), toolsHeight])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(language: String, layout: String, height: CGFloat, needsNext: Bool, compact: Bool = false) {
        guard rows.arrangedSubviews.isEmpty || self.language != language || self.layout != layout || keyHeight != height || self.needsNext != needsNext || self.compact != compact else { return }
        if self.language != language || self.layout != layout { symbols = 0; shifted = false }
        self.compact = compact; rows.spacing = compact ? 6 : 10; stack.spacing = compact ? 4 : 8
        toolsHeight.constant = compact ? 32 : 44; bottomInset.constant = compact ? -6 : -Self.bottomGap
        self.language = language; self.layout = layout; keyHeight = height; self.needsNext = needsNext; refresh()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { refresh() }
    }
    /// How far above the top row (beyond the 8pt gap) a touch still belongs to it. Fast thumbs land
    /// high on ㅂ…ㅔ; only empty tool-strip space is claimed, never its buttons.
    private static let topRowReach: CGFloat = 12
    private func keyPoint(_ point: CGPoint) -> CGPoint {
        let area = rows.convert(rows.bounds, to: self)
        guard point.y < area.minY - 8, point.y >= area.minY - 8 - Self.topRowReach, point.x >= area.minX - 8, point.x <= area.maxX + 8 else { return point }
        return CGPoint(x: point.x, y: area.minY)
    }
    private func toolControl(at point: CGPoint) -> Bool {
        guard !tools.isHidden, tools.alpha > 0.01 else { return false }
        let local = convert(point, to: tools)
        var view = tools.bounds.contains(local) ? tools.hitTest(local, with: nil) : nil
        while let current = view, current !== tools { if current is UIControl { return true }; view = current.superview }
        return false
    }
    private func nearestKey(at rawPoint: CGPoint, reach: [Int: Double] = [:]) -> KeyboardKeyButton? {
        let point = keyPoint(rawPoint)
        updateTouchGeometry()
        guard !listVisible, !emojiVisible, rows.convert(rows.bounds, to: self).insetBy(dx: -8, dy: -8).contains(point),
              let id = KeyboardTouchTarget.resolve(x: point.x, y: point.y, targets: touchTargets, reach: reach) else { return nil }
        return touchKeys[id]
    }
    private func updateTouchGeometry() {
        // Nested stack views finish arranging after their parent's layout callback.
        // Sample their final frames when a real event arrives, not during that callback.
        if touchGeometryDirty {
            rows.layoutIfNeeded()
            var frames = touchKeys.map { $0.convert($0.bounds, to: self) }
            let rowTops = Array(Set(frames.map { $0.minY.rounded() })).sorted()
            // Each row's outer keys own the inset beside them (for example around ㅁ and ㅣ),
            // so a tap there types the edge key rather than nothing.
            let area = rows.convert(rows.bounds, to: self)
            for top in rowTops {
                let row = frames.indices.filter { frames[$0].minY.rounded() == top && !frames[$0].isEmpty }
                if let first = row.min(by: { frames[$0].minX < frames[$1].minX }), frames[first].minX > area.minX {
                    frames[first] = CGRect(x: area.minX, y: frames[first].minY, width: frames[first].maxX - area.minX, height: frames[first].height)
                }
                if let last = row.max(by: { frames[$0].maxX < frames[$1].maxX }), frames[last].maxX < area.maxX {
                    frames[last] = CGRect(x: frames[last].minX, y: frames[last].minY, width: area.maxX - frames[last].minX, height: frames[last].height)
                }
            }
            touchTargets = touchKeys.enumerated().map { id, key in
                let frame = frames[id]
                return KeyboardTouchTarget(id: id, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, group: key.touchGroup, row: rowTops.firstIndex(of: frame.minY.rounded()) ?? 0, correctable: key.touchGroup == 1 || key.moakiBase != nil)
            }
            touchGeometryDirty = false
        }
    }
    /// Every dubeolsik jamo key's reach for the next tap; empty (plain geometry) at a word start.
    private func predictedReach() -> [Int: Double] {
        guard language == "ko", layout == "dubeolsik", symbols == 0 else { return [:] }
        updateTouchGeometry()
        var result: [Int: Double] = [:]
        for (id, key) in touchKeys.enumerated() where key.touchGroup == 1 && touchTargets.indices.contains(id) {
            if let reach = tapPrediction.reach(of: key.inputValue) { result[id] = reach }
        }
        return result
    }
    func resetTapPrediction(replaying inputs: [String] = []) {
        tapPrediction.reset()
        for input in inputs { tapPrediction.record(input) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point), keyPoint(point) == point || !toolControl(at: point), let key = nearestKey(at: point) {
            return key.touchGroup > 0 ? self : key
        }
        return super.hitTest(point, with: event)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        touchGeometryDirty = true
        if bounds.size != touchSize { cancelTaps(); touchSize = bounds.size }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelTaps() } }
    private func cancelTaps() {
        taps.removeAll(); touchSequence.cancelAll()
        touchKeys.forEach { if $0.touchGroup > 0 { $0.isHighlighted = false } }
    }
    private func highlightTaps() {
        let active = Set(touchSequence.pressedKeys)
        for (id, key) in touchKeys.enumerated() where key.touchGroup > 0 { key.isHighlighted = active.contains(id) }
    }
    private func commitTaps(_ commits: [KeyboardTouchSequence.Commit]) {
        // The sequence removes committed fingers before invoking document callbacks.
        for commit in commits where touchKeys.indices.contains(commit.key) {
            touchKeys[commit.key].sendActions(for: .touchUpInside)
        }
        highlightTaps()
    }
    // Touches on the surface arrive through KeyboardTouchRecognizer; the view's own, possibly delayed,
    // copies are ignored so nothing types twice. Controls (shift, delete, return) track their own.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
    private func beginTaps(_ touches: Set<UITouch>) {
        var pressed = 0
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) where touch.view === self && taps[ObjectIdentifier(touch)] == nil {
            let point = touch.location(in: self)
            let reach = predictedReach()
            guard let key = nearestKey(at: point, reach: reach), key.touchGroup > 0,
                  let id = touchKeys.firstIndex(of: key) else { continue }
            // Presses count before release so a finger still down shapes the next prediction.
            if key.touchGroup == 1 { tapPrediction.record(key.inputValue) } else { tapPrediction.reset() }
            nextPointer &+= 1; pressed += 1
            taps[ObjectIdentifier(touch)] = Tap(pointer: nextPointer, initialKey: id, origin: point, began: touch.timestamp, reach: key.touchGroup == 1 ? reach : [:], key: id)
            touchSequence.begin(nextPointer, key: id)
        }
        highlightTaps()
        // Haptics run after every touch of this event is recorded, never between two of them.
        for _ in 0..<pressed { onPress?() }
    }
    private func moveTap(_ touch: UITouch) {
        let identity = ObjectIdentifier(touch)
        guard var tap = taps[identity], touchKeys.indices.contains(tap.initialKey) else { return }
        let point = keyPoint(touch.location(in: self))
        if touchKeys[tap.initialKey].touchGroup == 2 {
            guard tap.cursor.active || touchSequence.contains(tap.pointer) else { return }
            let dx = point.x - tap.origin.x, dy = point.y - tap.origin.y
            let wasCursor = tap.cursor.active
            let delta = tap.cursor.update(dx: dx, dy: dy, elapsedMilliseconds: (touch.timestamp - tap.began) * 1000)
            if !wasCursor, tap.cursor.active {
                tapPrediction.reset()
                touchSequence.move(tap.pointer, key: nil)
                commitTaps(touchSequence.end(tap.pointer))
            }
            if tap.cursor.active {
                if delta != 0 { onCursor?(delta) }
            } else {
                tap.key = KeyboardTouchTarget.follow(x: point.x, y: point.y, targets: touchTargets, current: tap.key, group: 2, releaseSlack: KeyboardKeyButton.releaseSlack)
                touchSequence.move(tap.pointer, key: tap.key)
            }
        } else if touchSequence.contains(tap.pointer) {
            // A short drift onto shift, delete, space or past the edge keeps the letter.
            tap.key = KeyboardTouchTarget.follow(x: point.x, y: point.y, targets: touchTargets, current: tap.key, group: 1, releaseSlack: KeyboardKeyButton.releaseSlack, reach: tap.reach)
            touchSequence.move(tap.pointer, key: tap.key)
        }
        taps[identity] = tap
    }
    private func moveTaps(_ touches: Set<UITouch>) {
        for touch in touches { moveTap(touch) }; highlightTaps()
    }
    private func endTaps(_ touches: Set<UITouch>) {
        for touch in touches.sorted(by: { (taps[ObjectIdentifier($0)]?.pointer ?? 0) < (taps[ObjectIdentifier($1)]?.pointer ?? 0) }) {
            moveTap(touch)
            if let tap = taps.removeValue(forKey: ObjectIdentifier(touch)) { commitTaps(touchSequence.end(tap.pointer)) }
        }
        highlightTaps()
    }
    private func cancelTaps(_ touches: Set<UITouch>) {
        for touch in touches { if let tap = taps.removeValue(forKey: ObjectIdentifier(touch)) { touchSequence.cancel(tap.pointer) } }
        highlightTaps()
    }
    private func button(_ title: String, icon: String? = nil, special: Bool = false, events: UIControl.Event = .touchUpInside, action: (() -> Void)? = nil) -> KeyboardKeyButton {
        let key = KeyboardKeyButton(type: .custom)
        if let icon { key.setImage(UIImage(systemName: icon), for: .normal); key.setPreferredSymbolConfiguration(.init(pointSize: 23, weight: .regular), forImageIn: .normal) }
        else { key.setTitle(title, for: .normal) }
        key.accessibilityLabel = title; key.accessibilityIdentifier = "key-" + title
        key.titleLabel?.font = .systemFont(ofSize: title.count > 2 ? 16 : 24, weight: .regular)
        key.titleLabel?.adjustsFontSizeToFitWidth = true; key.titleLabel?.minimumScaleFactor = 0.65
        key.tintColor = Palette.ink; key.setTitleColor(key.tintColor, for: .normal)
        key.restingColor = special ? specialColor : keyColor
        key.pressedColor = dark ? UIColor(white: 0.43, alpha: 1) : UIColor(white: 0.66, alpha: 1)
        key.backgroundColor = key.restingColor; key.layer.cornerRadius = 8; key.layer.cornerCurve = .continuous
        key.layer.shadowColor = UIColor.black.cgColor; key.layer.shadowOffset = CGSize(width: 0, height: 1); key.layer.shadowRadius = 0; key.layer.shadowOpacity = dark ? 0 : 0.25
        key.heightAnchor.constraint(equalToConstant: renderedKeyHeight).isActive = true
        key.containsTouch = { [weak self, weak key] point in
            guard let self, let key else { return false }
            return self.nearestKey(at: key.convert(point, to: self)) === key
        }
        // Press feedback first: touch-down keys such as delete then act after it.
        key.addAction(UIAction { [weak self] _ in self?.onPress?() }, for: .touchDown)
        if let action { key.addAction(UIAction { _ in action() }, for: events) }
        return key
    }
    private func row(_ keys: [UIButton], inset: CGFloat = 0, weights: [CGFloat]? = nil) {
        touchKeys += keys.compactMap { $0 as? KeyboardKeyButton }
        let content = UIStackView(arrangedSubviews: keys); content.axis = .horizontal; content.spacing = 6
        if let weights {
            content.distribution = .fill
            for i in 1..<keys.count { keys[i].widthAnchor.constraint(equalTo: keys[0].widthAnchor, multiplier: weights[i] / weights[0]).isActive = true }
        } else { content.distribution = .fillEqually }
        let holder = UIView(); content.translatesAutoresizingMaskIntoConstraints = false; holder.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset), content.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset), content.topAnchor.constraint(equalTo: holder.topAnchor), content.bottomAnchor.constraint(equalTo: holder.bottomAnchor)])
        rows.addArrangedSubview(holder)
    }
    private func letters(_ titles: [String]) -> [UIButton] {
        titles.map { value in
            let key = button(value); key.inputValue = value; letterKeys.append(key)
            key.touchGroup = 1
            key.addAction(UIAction { [weak self, weak key] _ in
                guard let self, let key else { return }
                self.onInput?(key.inputValue)
                if self.shiftHeld { self.shiftUsed = true }
                else if self.shifted { self.shifted = false; self.updateLetterCase() }
            }, for: .touchUpInside)
            return key
        }
    }
    private var caseRedrawPending = false
    /// What each key types changes immediately; titles redraw on the next run-loop turn, coalesced,
    /// so a shift press does no layout work in the middle of fast typing.
    private func updateLetterCase() {
        guard symbols == 0, !(language == "ko" && ["cheonjiin", "moaki"].contains(layout)) else { return }
        let values = language == "ko" ? (shifted ? "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ" : "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ") + "ㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡ" : (shifted ? "QWERTYUIOPASDFGHJKLZXCVBNM" : "qwertyuiopasdfghjklzxcvbnm")
        for (key, value) in zip(letterKeys, values) { key.inputValue = String(value) }
        guard !caseRedrawPending else { return }
        caseRedrawPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            caseRedrawPending = false
            UIView.performWithoutAnimation {
                for key in self.letterKeys where key.title(for: .normal) != key.inputValue {
                    key.setTitle(key.inputValue, for: .normal)
                    key.accessibilityLabel = key.inputValue; key.accessibilityIdentifier = "key-" + key.inputValue
                    key.layoutIfNeeded()
                }
                self.shiftKey?.setImage(UIImage(systemName: self.shifted ? "shift.fill" : "shift"), for: .normal)
            }
        }
    }
    private func refresh() {
        cancelTaps()
        moakiPreview.removeFromSuperview()
        repeatTimer?.invalidate(); repeatTimer = nil; letterKeys = []; touchKeys = []; touchGeometryDirty = true; shiftHeld = false; tapPrediction.reset()
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        let shift = button(L("시프트"), icon: shifted ? "shift.fill" : "shift", special: true, events: .touchDown) { [weak self] in
            guard let self else { return }
            self.commitTaps(self.touchSequence.flush())
            self.shiftBeforePress = self.shifted; self.shiftHeld = true; self.shiftUsed = false
            self.shifted.toggle(); self.updateLetterCase()
        }
        shift.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if !self.shiftHeld { self.shifted.toggle() } // VoiceOver activation has no physical touch-down.
            else if self.shiftUsed { self.shifted = false }
            self.shiftHeld = false; self.updateLetterCase()
        }, for: .touchUpInside)
        shift.addAction(UIAction { [weak self] _ in
            guard let self, self.shiftHeld else { return }
            self.shiftHeld = false; self.shifted = self.shiftUsed ? false : self.shiftBeforePress; self.updateLetterCase()
        }, for: [.touchUpOutside, .touchCancel])
        shiftKey = shift
        let delete = button(L("삭제"), icon: "delete.left", special: true, events: .touchDown) { [weak self] in self?.tapPrediction.reset(); self?.onDelete?() }
        let held = UILongPressGestureRecognizer(target: self, action: #selector(deleteHeld(_:))); held.minimumPressDuration = 0.4; held.delegate = self; delete.addGestureRecognizer(held)
        let slide = UIPanGestureRecognizer(target: self, action: #selector(deleteSlid(_:))); slide.delegate = self; delete.addGestureRecognizer(slide)
        let normal: [[String]]
        if symbols > 0 {
            normal = symbols == 1 ? [Array("1234567890").map(String.init), Array("-/:;()₩&@\"").map(String.init), Array(".,?!'").map(String.init)] : [Array("[]{}#%^*+=").map(String.init), Array("_\\|~<>€£¥•").map(String.init), Array(".,?!'").map(String.init)]
            row(letters(normal[0])); row(letters(normal[1]))
            let page = button(symbols == 1 ? "#+=" : "123", special: true) { [weak self] in guard let self else { return }; self.symbols = self.symbols == 1 ? 2 : 1; self.refresh() }
            row([page] + letters(normal[2]) + [delete], weights: [1.5, 1, 1, 1, 1, 1, 1.5])
        } else if language == "ko" && layout == "cheonjiin" {
            for values in [["ㅣ","ㆍ","ㅡ"],["ㄱㅋㄲ","ㄴㄹ","ㄷㅌㄸ"],["ㅂㅍㅃ","ㅅㅎㅆ","ㅈㅊㅉ"],["ㅇㅁ","."]] { row(letters(values) + (values.count == 2 ? [delete] : [])) }
        } else if language == "ko" && layout == "moaki" {
            for (index, values) in MoakiLayout.rows.enumerated() {
                let keys = values.map { value -> UIButton in
                    if value == "⌫" { return delete }
                    if MoakiLayout.consonants.contains(value) { return moakiKey(value) }
                    return button(value) { [weak self] in self?.onInput?(value) }
                }
                row(keys, weights: MoakiLayout.weights(row: index).map { CGFloat($0) })
            }
        } else {
            normal = language == "ko" ? [(shifted ? "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ" : "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ").map(String.init), "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".map(String.init), "ㅋㅌㅊㅍㅠㅜㅡ".map(String.init)] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map { shifted ? String($0).uppercased() : String($0) } }
            row(letters(normal[0])); row(letters(normal[1]), inset: 16)
            row([shift] + letters(normal[2]) + [delete], weights: [1.3] + Array(repeating: 1, count: 7) + [1.3])
        }
        let numbers = button(symbols == 0 ? (layout == "moaki" && language == "ko" ? "!#1" : "123") : (language == "ko" ? "가나다" : "ABC"), special: true) { [weak self] in guard let self else { return }; self.symbols = self.symbols == 0 ? 1 : 0; self.refresh() }
        let space = button(L("스페이스")) { [weak self] in self?.onInput?(" ") }
        space.touchGroup = 2
        let enter = button(L("줄바꿈"), icon: "return", special: true) { [weak self] in self?.tapPrediction.reset(); self?.onInput?("\n") }
        enterKey = enter
        var bottom = [numbers, space, enter], weights: [CGFloat] = [1.5, 6, 1.5]
        if language == "ko", layout == "moaki", symbols == 0 {
            let languageKey = button("한/영", special: true) { [weak self] in self?.switchLanguage() }
            languageKey.titleLabel?.font = .systemFont(ofSize: 14)
            let nextMode = UILongPressGestureRecognizer(target: self, action: #selector(nextKeyboardHeld(_:))); languageKey.addGestureRecognizer(nextMode)
            let comma = button(",") { [weak self] in self?.onInput?(",") }
            comma.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(emojiHeld(_:))))
            let vowel = moakiKey(""); vowel.setTitle("ㅣ·ㅡ\n" + L("모음"), for: .normal)
            vowel.titleLabel?.numberOfLines = 2; vowel.titleLabel?.textAlignment = .center; vowel.titleLabel?.font = .systemFont(ofSize: 12)
            vowel.accessibilityLabel = L("모음")
            bottom = [numbers, languageKey, comma, space, vowel, enter]; weights = [1.4, 1, 1, 4.5, 1, 1.5]
        } else {
            let emoji = button(L("이모지"), icon: "face.smiling", special: true) { [weak self] in self?.setEmojiVisible(true) }
            bottom.insert(emoji, at: 1); weights.insert(1, at: 1); weights[weights.count - 2] -= 1
            if layout == "moaki" {
                let languageKey = button("한/영", special: true) { [weak self] in self?.switchLanguage() }
                languageKey.titleLabel?.font = .systemFont(ofSize: 14)
                bottom.insert(languageKey, at: 1); weights.insert(1, at: 1); weights[weights.count - 2] -= 1
            }
            if needsNext {
                let next = button(L("다음 키보드"), icon: "globe", special: true) { [weak self] in self?.onNextKeyboard?() }
                bottom.insert(next, at: 1); weights.insert(1, at: 1); weights[weights.count - 2] -= 1
            }
        }
        row(bottom, weights: weights)
        applyReturnKey()
        emojiPanel.configure(backTitle: language == "ko" ? "가나다" : "ABC", compact: compact)
        emojiBottomInset.constant = compact ? -6 : -8
        setNeedsLayout()
    }
    @objc private func nextKeyboardHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onNextKeyboard?() }
    }
    @objc private func emojiHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { setEmojiVisible(true) }
    }
    private func setEmojiVisible(_ visible: Bool) {
        guard visible != emojiVisible else { return }
        cancelTaps(); moakiPreview.removeFromSuperview()
        repeatTimer?.invalidate(); repeatTimer = nil
        emojiVisible = visible
        setListVisible(false)
        stack.isHidden = visible; emojiPanel.isHidden = !visible
        setNeedsLayout()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
    private func moakiKey(_ base: String) -> KeyboardKeyButton {
        let key = button(base.isEmpty ? "ㅣ" : base)
        key.moakiBase = base; key.numberHint = MoakiLayout.numbers[base]
        if let number = key.numberHint {
            key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: L("길게 누르면 {0}", number), actionHandler: { [weak self] _ in self?.onInput?(number); return true })]
        }
        key.accessibilityHint = L("자음에서 드래그해 모음을 입력하세요. →ㅏ ←ㅓ ↑ㅗ ↓ㅜ ↗ㅣ ↘ㅡ")
        key.onMoakiInput = { [weak self] value in self?.onInput?(value) }
        key.onMoakiPreview = { [weak self, weak key] value in
            guard let self, let key else { return }
            guard let value else { self.moakiPreview.removeFromSuperview(); return }
            let bubble = self.moakiPreview
            bubble.text = value; bubble.font = .systemFont(ofSize: 30); bubble.textAlignment = .center
            bubble.backgroundColor = self.keyColor; bubble.textColor = Palette.ink
            bubble.layer.cornerRadius = 10; bubble.clipsToBounds = true; bubble.isUserInteractionEnabled = false
            bubble.layer.borderWidth = 1; bubble.layer.borderColor = UIColor.separator.cgColor
            let frame = key.convert(key.bounds, to: self)
            bubble.frame = CGRect(x: min(max(0, frame.midX - 32), max(0, self.bounds.width - 64)), y: max(0, frame.minY - 56), width: 64, height: 52)
            self.addSubview(bubble)
        }
        return key
    }
    @objc private func deleteHeld(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            repeatStarted = ProcessInfo.processInfo.systemUptime; repeats = 0
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in Task { @MainActor in self?.repeatDelete() } }
            repeatTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        else if [.ended, .cancelled, .failed].contains(recognizer.state) { repeatTimer?.invalidate(); repeatTimer = nil }
    }
    /// One character per repeat, two after 20 repeats, then a word every third repeat after 3 seconds.
    private func repeatDelete() {
        repeats += 1
        switch DeleteRepeat.step(repeats: repeats, held: ProcessInfo.processInfo.systemUptime - repeatStarted) {
        case .characters(let count): for _ in 0..<count { onDelete?() }
        case .word: if repeats % 3 == 0 { onDeleteWord?() }
        }
    }
    @objc private func deleteSlid(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began: repeatTimer?.invalidate(); repeatTimer = nil; onDeleteSlide?(0)
        case .changed: onDeleteSlide?(DeleteSlide.count(dx: recognizer.translation(in: self).x))
        case .ended, .cancelled, .failed: onDeleteSlideEnd?()
        default: break
        }
    }
    /// The return key follows the field (KeyboardKit's return key types): search, send, go… show as a
    /// labelled accent key, others as the return glyph. Disabled while the field is empty if the host asks.
    func setReturnKey(_ type: UIReturnKeyType, enablesAutomatically: Bool, hasText: Bool) {
        let title: String? = switch type {
        case .go: L("이동")
        case .search, .google, .yahoo: L("검색")
        case .send: L("전송")
        case .done: L("완료")
        case .next: L("다음")
        case .join: L("참가")
        case .route: L("경로")
        case .continue: L("계속")
        case .emergencyCall: L("긴급 전화")
        default: nil
        }
        let style = ReturnKeyStyle(title: title, enabled: !(enablesAutomatically && !hasText))
        guard style != returnKeyStyle else { return }
        returnKeyStyle = style; applyReturnKey()
    }
    private func applyReturnKey() {
        guard let key = enterKey else { return }
        UIView.performWithoutAnimation {
            if let title = returnKeyStyle.title {
                key.setImage(nil, for: .normal); key.setTitle(title, for: .normal); key.accessibilityLabel = title
                key.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold); key.setTitleColor(Palette.onAccent, for: .normal)
                key.restingColor = Palette.accent
            } else {
                key.setTitle(nil, for: .normal); key.setImage(UIImage(systemName: "return"), for: .normal); key.accessibilityLabel = L("줄바꿈")
                key.setTitleColor(Palette.ink, for: .normal); key.restingColor = specialColor
            }
            key.backgroundColor = key.restingColor
            key.isEnabled = returnKeyStyle.enabled; key.alpha = returnKeyStyle.enabled ? 1 : 0.45
            key.layoutIfNeeded()
        }
    }
}

extension NativeKeyboardSurface: UIGestureRecognizerDelegate {
    /// Holding delete and then sliding hands the repeat over to the slide.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer.view === other.view
    }
}

/// Above the keys: a tappable shortcut expansion on the left, saved phrases and clipboard on the right.
@MainActor final class KeyboardToolStrip: UIView {
    var onExpand: ((TextShortcut) -> Void)?
    var onSnippets: (() -> Void)?
    var onClipboard: (() -> Void)?
    private let suggestion = UIButton(type: .system)
    private let snippets = UIButton(type: .system)
    private let clipboard = UIButton(type: .system)
    private var shortcut: TextShortcut?
    var clipboardEnabled = false { didSet { clipboard.isHidden = !clipboardEnabled } }
    override init(frame: CGRect) {
        super.init(frame: frame); accessibilityIdentifier = "tool-strip"
        suggestion.contentHorizontalAlignment = .leading; suggestion.titleLabel?.lineBreakMode = .byTruncatingTail
        suggestion.titleLabel?.font = .systemFont(ofSize: 16); suggestion.accessibilityIdentifier = "shortcut-suggestion"
        suggestion.addAction(UIAction { [weak self] _ in if let shortcut = self?.shortcut { self?.onExpand?(shortcut) } }, for: .touchUpInside)
        for (button, icon, label, identifier) in [(snippets, "text.quote", L("자주 쓰는 문구"), "tool-snippets"), (clipboard, "doc.on.clipboard", L("클립보드"), "tool-clipboard")] {
            button.setImage(UIImage(systemName: icon), for: .normal); button.tintColor = Palette.ink
            button.accessibilityLabel = label; button.accessibilityIdentifier = identifier
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        snippets.addAction(UIAction { [weak self] _ in self?.onSnippets?() }, for: .touchUpInside)
        clipboard.addAction(UIAction { [weak self] _ in self?.onClipboard?() }, for: .touchUpInside)
        clipboard.isHidden = true
        let line = UIStackView(arrangedSubviews: [suggestion, snippets, clipboard]); line.axis = .horizontal; line.spacing = 4
        line.translatesAutoresizingMaskIntoConstraints = false; addSubview(line)
        NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), line.trailingAnchor.constraint(equalTo: trailingAnchor), line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor)])
        showShortcut(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func showShortcut(_ value: TextShortcut?) {
        guard value != shortcut || suggestion.title(for: .normal) == nil else { return }
        shortcut = value
        UIView.performWithoutAnimation {
            suggestion.setTitle(value.map { $0.trigger + " → " + $0.expansion.replacingOccurrences(of: "\n", with: " ") } ?? " ", for: .normal)
            suggestion.isEnabled = value != nil; suggestion.accessibilityLabel = value.map { L("단축어 {0} 입력", $0.trigger) }
            suggestion.layoutIfNeeded()
        }
    }
}

/// Saved phrases or clipboard items; tapping one types it.
@MainActor final class KeyboardTextList: UIView {
    var onBack: (() -> Void)?
    var onSelect: ((String) -> Void)?
    var onClear: (() -> Void)?
    private let title = UILabel()
    private let clear = UIButton(type: .system)
    private let items = UIStackView()
    override init(frame: CGRect) {
        super.init(frame: frame); accessibilityIdentifier = "text-list"
        let back = UIButton(type: .system); back.setImage(UIImage(systemName: "keyboard"), for: .normal)
        back.setPreferredSymbolConfiguration(.init(pointSize: 23), forImageIn: .normal); back.tintColor = Palette.ink
        back.accessibilityLabel = L("자판으로 돌아가기"); back.accessibilityIdentifier = "text-list-back"
        back.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true
        title.font = .systemFont(ofSize: 15, weight: .semibold); title.textColor = Palette.secondary
        clear.setTitle(L("모두 지우기"), for: .normal); clear.accessibilityIdentifier = "text-list-clear"
        clear.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [back, title, clear]); header.axis = .horizontal; header.spacing = 8
        let scroll = UIScrollView(); scroll.alwaysBounceVertical = true
        items.axis = .vertical; items.spacing = 4; items.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(items)
        let layout = UIStackView(arrangedSubviews: [header, scroll]); layout.axis = .vertical; layout.spacing = 4
        layout.translatesAutoresizingMaskIntoConstraints = false; addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: leadingAnchor), layout.trailingAnchor.constraint(equalTo: trailingAnchor), layout.topAnchor.constraint(equalTo: topAnchor), layout.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            items.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), items.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), items.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), items.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), items.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(title value: String, items values: [String], empty: String, clearable: Bool) {
        title.text = value; clear.isHidden = !clearable
        items.arrangedSubviews.forEach { items.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard !values.isEmpty else {
            let label = UILabel(); label.text = empty; label.textColor = Palette.secondary; label.numberOfLines = 0; label.textAlignment = .center
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
            items.addArrangedSubview(label); return
        }
        for (index, text) in values.enumerated() {
            var style = UIButton.Configuration.filled()
            style.attributedTitle = AttributedString(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16)]))
            style.baseForegroundColor = Palette.ink; style.baseBackgroundColor = Palette.key
            style.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12); style.titleLineBreakMode = .byTruncatingTail
            style.background.cornerRadius = 8
            let button = UIButton(configuration: style)
            button.contentHorizontalAlignment = .leading; button.titleLabel?.numberOfLines = 2
            button.accessibilityIdentifier = "text-list-item-\(index)"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(text) }, for: .touchUpInside)
            items.addArrangedSubview(button)
        }
    }
}
