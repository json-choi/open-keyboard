import UIKit
import AudioToolbox
import KeyboardCore

@MainActor final class KeyboardViewController: NativeKeyboardInputController {
    private let store = SharedSettingsStore()
    private var settings = KeyboardSettings()
    private let typing = KoreanTypingSession()
    private lazy var inputGate = KeyboardHostInputGate(typing: typing)
    private var emptyHostRefresh: Task<Void, Never>?
    private var epoch: UInt64 = 0
    private var internalEdit = false
    private var lastObserved: DocumentContext?
    private var ownContexts = KeyboardContextAcknowledgements()
    private var typingWrite = false
    private var toolRefresh: Task<Void, Never>?
    /// Bumped by our own keys and cursor moves, so a deferred write they interrupt is dropped.
    private var userEdits: UInt64 = 0
    /// Lives only as long as this extension process; never written anywhere.
    private var clipboard = ClipboardHistory()
    private var pasteboardChange = -1
    private let keyFeedback = UIImpactFeedbackGenerator(style: .light)
    override func viewDidLoad() {
        super.viewDidLoad(); settings = store.read()
        surface.onInput = { [weak self] in self?.input($0) }
        surface.onListInput = { [weak self] in self?.input($0) }
        surface.onPress = { [weak self] in self?.pressFeedback() }
        surface.onDelete = { [weak self] in self?.delete() }
        surface.onDeleteWord = { [weak self] in self?.deleteWord() }
        surface.onDeleteSlide = { [weak self] count in self?.slideDelete(to: count) }
        surface.onDeleteSlideEnd = { [weak self] in self?.deleteSlide = nil }
        onNextInputMode = { [weak self] in self?.finishComposition(); self?.advanceToNextInputMode() }
        surface.onCursor = { [weak self] delta in guard let self else { return }; self.ownContexts.reset(); self.userEdits &+= 1; self.invalidate(); self.finishComposition(); self.editing { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta) } }
        surface.onLanguageChange = { [weak self] language in
            guard let self else { return }
            userEdits &+= 1; invalidate(); finishComposition(); settings = store.read(); settings.typingLanguage = language
            // Without Full Access the choice lasts until the keyboard closes.
            try? store.write(settings, permitted: hasFullAccess)
            configure(language: language, layout: settings.layout, keyHeight: CGFloat(settings.keyHeight))
            lastObserved = capture(); scheduleTools()
        }
        surface.tools.onExpand = { [weak self] in self?.expand($0) }
        surface.onOpenClipboard = { [weak self] in self?.refreshClipboard(); return self?.clipboard.items ?? [] }
        surface.onClearClipboard = { [weak self] in self?.clipboard.clear() }
        configure()
    }
    private func configure() {
        surface.snippets = settings.snippets
        // UIPasteboard is unavailable to a keyboard without Full Access.
        surface.tools.clipboardEnabled = settings.clipboardHistory && hasFullAccess
        if !settings.clipboardHistory { clipboard.clear() }
        configure(language: settings.typingLanguage, layout: settings.layout, keyHeight: CGFloat(settings.keyHeight))
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); settings = store.read(); feedbackLedger.reset(); configure()
        updateReturnKey(); if settings.haptics { keyFeedback.prepare() }
        KeyboardActivationStore().record(fullAccess: hasFullAccess)
        refreshClipboard()
        lastObserved = capture(); scheduleTools()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); invalidate(); finishComposition(); ownContexts.reset(); lastObserved = nil; surface.tools.showShortcut(nil) }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) { super.viewWillTransition(to: size, with: coordinator); coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.configure() } }
    /// Reads the pasteboard text only when its change count moved, and only with the history on.
    private func refreshClipboard() {
        guard settings.clipboardHistory, hasFullAccess else { return }
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != pasteboardChange else { return }
        pasteboardChange = pasteboard.changeCount
        if pasteboard.hasStrings { clipboard.add(pasteboard.string) }
    }
    private func capture() -> DocumentContext? {
        // Never project an old draft while the proxy's empty state is unresolved.
        guard !inputGate.isWaiting, textDocumentProxy.hasText || !typing.hasHostState else { return nil }
        return captureTypingContext()
    }
    private func captureTypingContext() -> DocumentContext? { typing.includingComposition(in: captureRaw()) }
    private func captureRaw() -> DocumentContext? {
        // During dismissal/rehosting UIKit can return nil from this Objective-C
        // getter despite its nonoptional Swift signature. Reading it as UUID
        // traps before a Swift optional check can run. Keep the ObjC result
        // optional and reject detached contexts instead of inventing an identity.
        guard let proxy = textDocumentProxy as? NSObject,
              let documentID = proxy.value(forKey: "documentIdentifier") as? UUID else { return nil }
        return DocumentContext(documentID: documentID, epoch: epoch, before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText, after: textDocumentProxy.documentContextAfterInput ?? "")
    }
    private func editing(_ action: () -> Void) {
        let nested = internalEdit
        if !nested { typingWrite = false }
        internalEdit = true; action(); internalEdit = nested
        if !nested, !inputGate.isWaiting { lastObserved = captureTypingContext() }
    }
    override func textDidChange(_ textInput: UITextInput?) { super.textDidChange(textInput); hostChanged(); updateReturnKey(); refreshClipboard() }
    private func updateReturnKey() {
        // Some hosts omit our marked Korean text from hasText, and callbacks can precede
        // the local composing write. A live composition still makes Return actionable.
        let hasComposition = typing.hasActiveComposition && !inputGate.isWaiting
        surface.setReturnKey(textDocumentProxy.returnKeyType ?? .default, enablesAutomatically: textDocumentProxy.enablesReturnKeyAutomatically ?? false, hasText: textDocumentProxy.hasText || hasComposition)
    }
    override func selectionDidChange(_ textInput: UITextInput?) { super.selectionDidChange(textInput); hostChanged(); updateReturnKey() }
    private func hostChanged() {
        guard !internalEdit else { return }
        if reconcileEmptyHost() { return }
        let current = captureTypingContext()
        guard current != lastObserved else { return }
        if ownContexts.contains(current, now: ProcessInfo.processInfo.systemUptime) { return }
        // The proxy reports our own composing writes late; that is not the user moving the cursor.
        if typing.recognizes(captureRaw()) { return }
        ownContexts.reset(); invalidate(); finishComposition(); lastObserved = capture(); scheduleTools()
    }
    private func invalidate() {
        toolRefresh?.cancel(); toolRefresh = nil
        epoch &+= 1; lastObserved?.epoch = epoch
    }
    /// Ends composition for a reason outside typing (cursor, switch, dismissal), so earlier states are forgotten.
    private func finishComposition() {
        emptyHostRefresh?.cancel(); emptyHostRefresh = nil; inputGate.cancel()
        editing { typing.finish(port: ProxyPort(owner: self)) }
        typing.resetHostState(); surface.resetTapPrediction()
    }
    private func handleHostInput(_ outcome: KeyboardHostInputGate.Outcome) {
        // Do not rely on a host sending another textDidChange after our key has finished.
        defer { updateReturnKey() }
        switch outcome {
        case .waiting:
            guard emptyHostRefresh == nil else { return }
            invalidate(); surface.tools.showShortcut(nil)
            emptyHostRefresh = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
                    guard let self, view.window != nil else { return }
                    _ = reconcileEmptyHost()
                    if !inputGate.isWaiting { return }
                }
            }
        case let .cleared(replayed):
            emptyHostRefresh?.cancel(); emptyHostRefresh = nil
            ownContexts.reset(); invalidate()
            surface.resetTapPrediction(replaying: replayed.map { event in
                if case let .input(value, _, _) = event { return value }
                return ""
            })
            lastObserved = captureTypingContext(); scheduleTools()
        case .abandoned:
            emptyHostRefresh?.cancel(); emptyHostRefresh = nil
            ownContexts.reset(); invalidate(); surface.resetTapPrediction()
            lastObserved = captureTypingContext(); scheduleTools()
        case .applied:
            emptyHostRefresh?.cancel(); emptyHostRefresh = nil
        }
    }
    /// Empty flags can lag marked writes. Confirm them without ending a live word or its touch prediction.
    private func reconcileEmptyHost() -> Bool {
        guard inputGate.isWaiting || (typing.hasHostState && !textDocumentProxy.hasText) else { return false }
        let previous = lastObserved, hadEvents = inputGate.hasPendingEvents
        var outcome = KeyboardHostInputGate.Outcome.applied
        editing { outcome = inputGate.observe(port: ProxyPort(owner: self), now: ProcessInfo.processInfo.systemUptime) }
        handleHostInput(outcome)
        if outcome == .applied {
            if hadEvents { scheduleTools(); return true }
            lastObserved = previous
            return false
        }
        return true
    }
    /// The press is counted at once; the vibration and click run after the touch event is handled,
    /// so the Taptic call never sits between touch handling and the next key.
    private func feedback() {
        let haptics = settings.haptics, sound = settings.sound && hasFullAccess
        guard haptics || sound else { return }
        DispatchQueue.main.async { [keyFeedback] in
            if haptics { keyFeedback.impactOccurred(); keyFeedback.prepare() }
            if sound { AudioServicesPlaySystemSound(1104) }
        }
    }
    /// Keys give feedback on touch-down; the input that follows each press stays silent.
    private var feedbackLedger = KeyFeedbackLedger()
    private func pressFeedback() { if feedbackLedger.press(at: ProcessInfo.processInfo.systemUptime) { feedback() } }
    private func inputFeedback() { if feedbackLedger.input(at: ProcessInfo.processInfo.systemUptime) { feedback() } }
    private func input(_ value: String) {
        userEdits &+= 1; invalidate(); inputFeedback()
        var outcome = KeyboardHostInputGate.Outcome.applied
        let event: KeyboardHostInputGate.Event = value == "\n" && (textDocumentProxy.returnKeyType ?? .default) != .default
            ? .returnAction : .input(value, language: settings.typingLanguage, layout: settings.layout)
        editing { outcome = inputGate.submit(event, port: ProxyPort(owner: self), now: ProcessInfo.processInfo.systemUptime) }
        handleHostInput(outcome)
        guard outcome == .applied else { return }
        scheduleTools()
    }
    /// Keep the composition commit and Return in separate proxy transactions. Otherwise
    /// single-line hosts may treat the combined text as a paste and turn the newline into a space.
    private func returnAfterComposition() {
        guard let document = captureRaw()?.documentID else { return }
        let expected = epoch, edits = userEdits
        DispatchQueue.main.async { [weak self] in
            guard let self, view.window != nil, epoch == expected, userEdits == edits,
                  captureRaw()?.documentID == document else { return }
            editing { self.textDocumentProxy.insertText("\n"); self.typingWrite = true }
            typing.resetHostState(); updateReturnKey(); scheduleTools()
        }
    }
    private func delete() {
        userEdits &+= 1; invalidate(); inputFeedback()
        var outcome = KeyboardHostInputGate.Outcome.applied
        editing { outcome = inputGate.submit(.delete, port: ProxyPort(owner: self), now: ProcessInfo.processInfo.systemUptime) }
        handleHostInput(outcome)
        guard outcome == .applied else { return }
        scheduleTools()
    }
    /// Held delete past 3 seconds: the last word and the spaces after it, as whole characters.
    private func deleteWord() {
        userEdits &+= 1; invalidate()
        var outcome = KeyboardHostInputGate.Outcome.applied
        editing { outcome = inputGate.submit(.deleteWord, port: ProxyPort(owner: self), now: ProcessInfo.processInfo.systemUptime) }
        handleHostInput(outcome)
        guard outcome == .applied else { return }
        surface.resetTapPrediction(); scheduleTools()
    }
    private var deleteSlide: DeleteSlide?
    /// Sliding left from delete removes characters live; sliding back restores exactly those.
    private func slideDelete(to target: Int) {
        if deleteSlide == nil { finishComposition(); deleteSlide = DeleteSlide(before: textDocumentProxy.documentContextBeforeInput) }
        guard var slide = deleteSlide else { return }
        let change = slide.move(to: target); deleteSlide = slide
        guard change.delete > 0 || !change.restore.isEmpty else { return }
        userEdits &+= 1; invalidate(); inputFeedback()
        editing {
            for _ in 0..<change.delete { textDocumentProxy.deleteBackward() }
            if !change.restore.isEmpty { textDocumentProxy.insertText(change.restore) }
        }
        scheduleTools()
    }
    /// After a typing pause, offer the shortcut whose trigger is the whole last word.
    private func scheduleTools() {
        toolRefresh?.cancel()
        guard !settings.shortcuts.isEmpty else { surface.tools.showShortcut(nil); return }
        let expected = epoch
        toolRefresh = Task { @MainActor [weak self] in
            // Wait for a pause, so reading the field never lands between two key presses.
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self, epoch == expected, view.window != nil else { return }
            surface.tools.showShortcut(TextShortcuts.match(before: capture()?.before, shortcuts: settings.shortcuts))
        }
    }
    /// Replaces the trigger only if the field still ends with it as a whole word.
    private func expand(_ shortcut: TextShortcut) {
        finishComposition()
        surface.tools.showShortcut(nil)
        guard textDocumentProxy.selectedText?.isEmpty != false,
              TextShortcuts.match(before: textDocumentProxy.documentContextBeforeInput, shortcuts: [shortcut]) != nil else { return }
        userEdits &+= 1; invalidate(); inputFeedback()
        editing {
            for _ in shortcut.trigger { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(shortcut.expansion)
        }
        typing.resetHostState(); scheduleTools()
    }
    private final class ProxyPort: PartialEditPort {
        unowned let owner: KeyboardViewController
        private var endedComposition = false
        init(owner: KeyboardViewController) { self.owner = owner }
        var supportsMarkedComposition: Bool { true }
        func setMarkedComposition(_ text: String) {
            owner.editing { owner.textDocumentProxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0)); owner.typingWrite = true }
        }
        func commitMarkedComposition(_ text: String) {
            endedComposition = true
            owner.editing { owner.textDocumentProxy.insertText(text); owner.typingWrite = true }
        }
        func endMarkedComposition() { endedComposition = true; owner.editing { owner.textDocumentProxy.unmarkText() } }
        var hasText: Bool? { owner.textDocumentProxy.hasText }
        func read() -> DocumentContext? {
            let current = owner.captureRaw()
            if owner.internalEdit && owner.typingWrite { owner.ownContexts.record(current, now: ProcessInfo.processInfo.systemUptime) }
            return current
        }
        func deleteBackward() { owner.editing { owner.textDocumentProxy.deleteBackward(); owner.typingWrite = true } }
        func insert(_ text: String) {
            if text == "\n", endedComposition, (owner.textDocumentProxy.returnKeyType ?? .default) != .default {
                owner.returnAfterComposition(); return
            }
            owner.editing { owner.textDocumentProxy.insertText(text); owner.typingWrite = true }
        }
    }
}
