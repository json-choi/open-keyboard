package io.github.jsonchoi.openkeyboard

import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.TextView
import io.github.jsonchoi.openkeyboard.core.CheonjiinComposer
import io.github.jsonchoi.openkeyboard.core.DeleteRepeat
import io.github.jsonchoi.openkeyboard.core.EditorReading
import io.github.jsonchoi.openkeyboard.core.HangulComposer
import io.github.jsonchoi.openkeyboard.core.InputPrivacyPolicy
import io.github.jsonchoi.openkeyboard.core.KeyboardSelectionTracker
import io.github.jsonchoi.openkeyboard.core.MoakiGesture
import io.github.jsonchoi.openkeyboard.core.MoakiLayout
import io.github.jsonchoi.openkeyboard.core.Selection
import io.github.jsonchoi.openkeyboard.core.TextShortcut
import io.github.jsonchoi.openkeyboard.core.TextShortcuts

/** The input method. Everything runs on the device; the app has no network permission. */
class KeyboardService : InputMethodService() {
    private lateinit var settings: SettingsStore
    private var root: LinearLayout? = null
    private var keys: KeyboardTouchColumn? = null
    private var strip: SuggestionStrip? = null
    private var emojiPanel: NativeEmojiPanel? = null
    private var emojiVisible = false
    private var emojiPreferredHeight = 0
    private val letterKeys = mutableListOf<Pair<Button, String>>()
    private var shiftKey: Button? = null
    private val hangul = HangulComposer()
    private val cheonjiin = CheonjiinComposer()
    private var moakiPreview: PopupWindow? = null
    private var alternativesPopup: PopupWindow? = null
    private val handler = Handler(Looper.getMainLooper())
    private var repeatDelete: Runnable? = null
    private val selectionTracker = KeyboardSelectionTracker()
    private var selection: Selection
        get() = selectionTracker.selection
        set(value) { selectionTracker.reset(value) }
    private var sensitive = true
    private var mode = "ko"
    private var shift = false
    private var caps = false
    private var shiftAt = 0L
    private var shiftHeld = false
    private var shiftUsed = false
    private var shiftBeforePress = false
    private var capsBeforePress = false
    private var composingText = ""
    private var compositionStart = -1
    private var expectedSelection: Selection? = null
        set(value) {
            field = value
            if (value != null) selectionTracker.expect(value)
        }
    private var ownEdit = false
    private var shortcuts: List<TextShortcut> = emptyList()
    private var snippets: List<String> = emptyList()
    /** Reads around the caret. Never called for password variants or fields with unknown input class. */
    private fun read(): EditorReading? {
        if (sensitive) return null
        val connection = currentInputConnection ?: return null
        if (Build.VERSION.SDK_INT >= 31) {
            val surrounding = connection.getSurroundingText(4096, 4096, 0) ?: return null
            if (surrounding.offset < 0) return null
            val low = minOf(surrounding.selectionStart, surrounding.selectionEnd)
            val high = maxOf(surrounding.selectionStart, surrounding.selectionEnd)
            val text = surrounding.text.toString()
            if (low !in 0..text.length || high !in low..text.length) return null
            val observed = Selection(surrounding.offset + surrounding.selectionStart, surrounding.offset + surrounding.selectionEnd)
            return observeReading(EditorReading(observed, text.take(low), if (low == high) null else text.substring(low, high), text.substring(high)))
        }
        val extracted = connection.getExtractedText(ExtractedTextRequest().apply { hintMaxChars = 8192; hintMaxLines = 8 }, 0) ?: return null
        if (extracted.text == null || extracted.text.length > 12288 || extracted.startOffset < 0) return null
        val observed = Selection(extracted.startOffset + extracted.selectionStart, extracted.startOffset + extracted.selectionEnd)
        val before = connection.getTextBeforeCursor(4096, 0)?.toString() ?: return null
        val after = connection.getTextAfterCursor(4096, 0)?.toString() ?: return null
        val selected = if (observed.collapsed) null else connection.getSelectedText(0)?.toString() ?: return null
        return observeReading(EditorReading(observed, before, selected, after))
    }
    override fun onCreate() { super.onCreate(); settings = SettingsStore(this) }
    override fun onWindowShown() {
        super.onWindowShown()
        window?.window?.let { imeWindow ->
            // Draw the same input surface behind the gesture area instead of leaving a separate
            // system-colored strip below the last key row. The root applies navigation insets.
            // Edge-to-edge is the default from Android 15; older releases need the opt-in.
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT >= 30) imeWindow.setDecorFitsSystemWindows(false)
            @Suppress("DEPRECATION")
            imeWindow.navigationBarColor = android.graphics.Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= 28) {
                @Suppress("DEPRECATION")
                imeWindow.navigationBarDividerColor = android.graphics.Color.TRANSPARENT
            }
            if (Build.VERSION.SDK_INT >= 29) imeWindow.isNavigationBarContrastEnforced = false
            if (Build.VERSION.SDK_INT >= 30) {
                val mask = android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                imeWindow.insetsController?.setSystemBarsAppearance(if (AppUi.dark(this)) 0 else mask, mask)
            } else {
                @Suppress("DEPRECATION")
                val light = View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                @Suppress("DEPRECATION")
                imeWindow.decorView.systemUiVisibility =
                    (imeWindow.decorView.systemUiVisibility and light.inv()) or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    (if (AppUi.dark(this)) 0 else light)
            }
            root?.requestApplyInsets()
        }
    }
    override fun onCreateInputView(): View {
        val column = BoundedKeyboardColumn().apply { orientation = LinearLayout.VERTICAL; setPadding(dp(3), dp(3), dp(3), dp(4)) }
        column.setBackgroundColor(AppUi.keyboardBackground(this))
        column.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val safe = insets.getInsets(android.view.WindowInsets.Type.navigationBars() or android.view.WindowInsets.Type.captionBar() or android.view.WindowInsets.Type.displayCutout())
                view.setPadding(dp(3) + safe.left, dp(3), dp(3) + safe.right, dp(6) + safe.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(dp(3) + insets.systemWindowInsetLeft, dp(3), dp(3) + insets.systemWindowInsetRight, dp(6) + insets.systemWindowInsetBottom)
            }
            insets
        }
        strip = SuggestionStrip(this, ::insertSnippet)
        column.addView(strip, LinearLayout.LayoutParams(-1, dp(STRIP_HEIGHT)))
        keys = KeyboardTouchColumn(this).apply {
            orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_LTR; onSpaceCursor = ::moveCursor; onTouchStart = ::dismissAlternatives; onPress = ::keyFeedback
            claimedAbove = ::stripClaims
        }
        column.addView(keys, LinearLayout.LayoutParams(-1, -2))
        emojiPanel = NativeEmojiPanel(this, settings, ::input, ::delete) { showEmoji(false) }.apply { visibility = View.GONE }
        column.addView(emojiPanel, LinearLayout.LayoutParams(-1, 0))
        root = column
        renderKeys(); updateStrip()
        return column
    }
    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        showEmoji(false)
        selection = Selection(attribute?.initialSelStart ?: -1, attribute?.initialSelEnd ?: -1)
        clearComposition(); expectedSelection = null
        sensitive = isSensitive(attribute)
        val inputClass = (attribute?.inputType ?: 0) and InputType.TYPE_MASK_CLASS
        mode = if (inputClass in listOf(InputType.TYPE_CLASS_NUMBER, InputType.TYPE_CLASS_PHONE, InputType.TYPE_CLASS_DATETIME)) "number" else settings.typingLanguage
        if (attribute?.inputType?.and(InputType.TYPE_MASK_VARIATION) in listOf(InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS, InputType.TYPE_TEXT_VARIATION_URI, InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS)) mode = "en"
        shift = false; caps = false
        renderKeys()
    }
    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting); sensitive = isSensitive(info)
        // Settings may have changed in the app since the last field; reread them per field.
        shortcuts = settings.shortcuts; snippets = settings.snippets
        // A host can hide/show the same editor without starting another input session.
        // Restore the key surface even when the previous view closed in emoji mode.
        showEmoji(false)
        renderKeys(); updateStrip()
    }
    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        val next = Selection(newSelStart, newSelEnd)
        val expected = expectedSelection
        val matchingComposition = composingText.isNotEmpty() && next.collapsed && candidatesEnd >= 0 && next.end == candidatesEnd && candidatesStart == compositionStart
        // A host may commit/cancel the composing span without moving the caret. A matching
        // predicted position acknowledges the cursor, not ownership of the old composing text.
        // Older callbacks must still leave a newer in-flight composition alone.
        val compositionRemoved = composingText.isNotEmpty() && next == selection && candidatesStart < 0 && candidatesEnd < 0
        val acknowledged = selectionTracker.acknowledge(Selection(oldSelStart, oldSelEnd), next)
        if (ownEdit || !compositionRemoved && (acknowledged || next == expected || matchingComposition)) { if (next == expected) expectedSelection = null; return }
        if (oldSelStart != newSelStart || oldSelEnd != newSelEnd || composingText.isNotEmpty()) {
            expectedSelection = null; selection = next
            clearComposition(); currentInputConnection?.finishComposingText(); keys?.resetPrediction(); strip?.suggest(null)
        }
    }
    override fun onFinishInputView(finishingInput: Boolean) { finishComposition(); clearSession(); super.onFinishInputView(finishingInput) }
    override fun onFinishInput() { clearSession(); super.onFinishInput() }
    override fun onWindowHidden() { finishComposition(); clearSession(); super.onWindowHidden() }
    override fun onDestroy() { stopDeleteRepeat(); clearComposition(); super.onDestroy() }
    /** The strip shows only for users with shortcuts or snippets; otherwise the keys keep its height. */
    private fun updateStrip() {
        val visible = !emojiVisible && (shortcuts.isNotEmpty() || snippets.isNotEmpty())
        strip?.visibility = if (visible) View.VISIBLE else View.GONE
        strip?.setSnippets(snippets); strip?.suggest(null)
        // Reach into the strip's empty bottom: keys stay where they are drawn, the touch area grows upward.
        val reach = if (visible) dp(TOP_ROW_REACH) else 0
        keys?.let { column ->
            column.setPadding(0, reach, 0, 0)
            column.layoutParams = (column.layoutParams as LinearLayout.LayoutParams).apply { topMargin = -reach }
        }
    }
    private fun clearSession() { keys?.cancelTouches(); dismissAlternatives(); shiftHeld = false; moakiPreview?.dismiss(); moakiPreview = null; sensitive = true; stopDeleteRepeat(); clearComposition(); expectedSelection = null; selectionTracker.reset(selection); strip?.suggest(null) }
    private fun clearComposition() { hangul.clear(); cheonjiin.clear(); composingText = ""; compositionStart = -1 }
    private fun observeReading(read: EditorReading): EditorReading {
        // A host may clear the field (for example after sending) before a selection callback reaches us.
        // Drop local state only; reading text must never write it back.
        if (!ownEdit && composingText.isNotEmpty() && read.selection.valid && read.selection.collapsed &&
            read.before.isEmpty() && read.selected.isNullOrEmpty() && read.after.isEmpty()) {
            clearComposition(); expectedSelection = null; selectionTracker.reset(read.selection)
            keys?.resetPrediction()
        } else selectionTracker.observe(read.selection)
        return read
    }
    private fun showEmoji(visible: Boolean) {
        if (visible) {
            emojiPanel?.refreshLanguage()
            keys?.cancelTouches(); keys?.resetPrediction(); stopDeleteRepeat(); finishComposition()
            moakiPreview?.dismiss(); moakiPreview = null
            emojiPreferredHeight = root?.let { it.height - it.paddingTop - it.paddingBottom }?.takeIf { it > 0 } ?: dp(settings.keyHeight * 4 + STRIP_HEIGHT)
        }
        emojiVisible = visible
        keys?.visibility = if (visible) View.GONE else View.VISIBLE
        emojiPanel?.visibility = if (visible) View.VISIBLE else View.GONE
        updateStrip()
        root?.requestLayout()
    }
    private fun finishComposition() { if (compositionStart >= 0) currentInputConnection?.finishComposingText(); clearComposition() }
    private fun expectedWrite(next: Selection?, write: () -> Boolean): Boolean {
        val previous = selection
        expectedSelection = next
        val accepted = write()
        if (!accepted) { expectedSelection = null; selection = previous }
        return accepted
    }
    private fun compose(value: String) {
        val connection = currentInputConnection ?: return
        if (compositionStart < 0) compositionStart = selection.low
        composingText = value
        val next = if (compositionStart >= 0) Selection(compositionStart + value.length, compositionStart + value.length) else null
        // A host that rejects composing spans still got nothing half-written; start the next syllable fresh.
        if (!expectedWrite(next) { connection.setComposingText(value, 1) }) clearComposition()
    }
    private fun input(value: String) {
        if (mode == "ko" && settings.layout in setOf("dubeol", "moaki") && value.length in 1..2 && value.all { it in "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ" }) {
            value.forEach { hangul.input(it) }; compose(hangul.text)
        }
        else { finishComposition(); commit(value) }
        if (shiftHeld) shiftUsed = true
        else if (shift && !caps) { shift = false; updateLetterCase() }
        suggestShortcut()
    }
    private fun inputCheonjiin(value: String) {
        val result = if (value.length == 1 && value[0] in "ㅣㆍㅡ") cheonjiin.vowel(value[0])
            else cheonjiin.consonant(value, android.os.SystemClock.uptimeMillis())
        compose(result)
        suggestShortcut()
    }
    private fun insertSnippet(value: String) {
        finishComposition(); commit(value); strip?.suggest(null)
    }
    /** Reads only the last word before the cursor, locally, and only when the user registered shortcuts. */
    private fun suggestShortcut() {
        if (shortcuts.isEmpty() || sensitive) return
        val before = currentInputConnection?.getTextBeforeCursor(TextShortcuts.MAX_TRIGGER * 4, 0)?.toString()
        val match = before?.let { TextShortcuts.match(it, shortcuts) }
        strip?.suggest(match) { match?.let(::expand) }
    }
    private fun expand(shortcut: TextShortcut) {
        finishComposition()
        val connection = currentInputConnection ?: return
        val before = connection.getTextBeforeCursor(TextShortcuts.MAX_TRIGGER * 4, 0)?.toString()
        // The text may have changed since the suggestion appeared; replace only a still-matching word.
        if (sensitive || before == null || TextShortcuts.match(before, listOf(shortcut)) == null || !selection.collapsed) return
        val start = selection.low - shortcut.trigger.length
        expectedSelection = if (selection.valid && start >= 0) Selection(start + shortcut.expansion.length, start + shortcut.expansion.length) else null
        connection.beginBatchEdit()
        connection.deleteSurroundingText(shortcut.trigger.length, 0)
        connection.commitText(shortcut.expansion, 1)
        connection.endBatchEdit()
    }
    private fun commit(value: String) {
        val connection = currentInputConnection ?: return
        val next = if (selection.valid) Selection(selection.low + value.length, selection.low + value.length) else null
        expectedWrite(next) { connection.commitText(value, 1) }
    }
    private fun delete() {
        val connection = currentInputConnection ?: return
        if (composingText.isNotEmpty()) {
            val next = if (settings.layout == "cheonjiin") cheonjiin.backspace() else hangul.backspace()
            compose(next)
            if (next.isEmpty()) finishComposition()
            suggestShortcut()
            return
        }
        if (!selection.collapsed && selection.valid) { commit(""); return }
        if (sensitive) { connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL)); connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL)); return }
        val before = connection.getTextBeforeCursor(256, 0)?.toString() ?: return
        if (before.isEmpty()) return
        val length = Unicode.previousLength(before)
        if (length <= 0) return
        val next = if (selection.low >= length) Selection(selection.low - length, selection.low - length) else null
        expectedWrite(next) { connection.deleteSurroundingText(length, 0) }
        suggestShortcut()
    }
    private fun moveCursor(direction: Int) {
        finishComposition(); strip?.suggest(null)
        val connection = currentInputConnection ?: return
        if (sensitive) {
            val code = if (direction < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
            repeat(kotlin.math.abs(direction).coerceAtMost(32)) { connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code)); connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code)) }; return
        }
        val read = read() ?: return
        var cursor = if (direction < 0) read.selection.low else read.selection.high
        var available = if (direction < 0) read.before else read.after
        val count = (kotlin.math.abs(direction).coerceAtMost(32) - if (read.selection.collapsed) 0 else 1).coerceAtLeast(0)
        repeat(count) {
            val step = if (direction < 0) Unicode.previousLength(available) else Unicode.nextLength(available)
            cursor += if (direction < 0) -step else step
            available = if (direction < 0) available.dropLast(step) else available.drop(step)
        }
        if (cursor < 0) return
        expectedWrite(Selection(cursor, cursor)) { connection.setSelection(cursor, cursor) }
    }
    private fun enter() {
        finishComposition(); strip?.suggest(null)
        val info = currentInputEditorInfo
        val action = info?.imeOptions?.and(EditorInfo.IME_MASK_ACTION) ?: EditorInfo.IME_ACTION_NONE
        if (action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED && info?.imeOptions?.and(EditorInfo.IME_FLAG_NO_ENTER_ACTION) == 0)
            currentInputConnection?.performEditorAction(action) else commit("\n")
    }
    private fun renderKeys() {
        moakiPreview?.dismiss(); moakiPreview = null; dismissAlternatives()
        val container = keys ?: return
        container.resetKeys(); letterKeys.clear(); shiftKey = null; shiftHeld = false
        container.resetPrediction(); container.tapPredictionEnabled = mode == "ko" && settings.layout == "dubeol"
        container.keepsPrediction = { it === shiftKey }
        container.removeAllViews()
        val alphabet = mode == "en" || mode == "ko" && settings.layout == "dubeol"
        if (alphabet) row("1234567890".map(Char::toString), container,
            height = (settings.keyHeight * .85f).toInt(), alphabet = true)
        val rows: List<List<String>> = when (mode) {
            "number" -> listOf(listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"), listOf("@", "#", "$", "%", "&", "*", "(", ")", "-", "+"), listOf("기호", "!", "?", ":", ";", "/", ".", "⌫"))
            "symbol" -> listOf(listOf("[", "]", "{", "}", "<", ">", "=", "_", "\\", "|"), listOf("₩", "€", "£", "¥", "~", "`", "^", "°", "•", "…"), listOf("숫자", "'", "\"", ",", "!", "?", "/", "⌫"))
            "en" -> listOf("qwertyuiop".map { if (shift || caps) it.uppercaseChar().toString() else it.toString() }, "asdfghjkl".map { if (shift || caps) it.uppercaseChar().toString() else it.toString() }, listOf("⇧") + "zxcvbnm".map { if (shift || caps) it.uppercaseChar().toString() else it.toString() } + "⌫")
            else -> if (settings.layout == "moaki") MoakiLayout.rows
            else if (settings.layout == "cheonjiin") listOf(listOf("ㅣ", "ㆍ", "ㅡ"), listOf("ㄱㅋㄲ", "ㄴㄹ", "ㄷㅌㄸ"), listOf("ㅂㅍㅃ", "ㅅㅎㅆ", "ㅈㅊㅉ"), listOf("ㅇㅁ", ".", "⌫"))
            else listOf((if (shift) "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ" else "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ").map(Char::toString), "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".map(Char::toString), listOf("⇧") + "ㅋㅌㅊㅍㅠㅜㅡ".map(Char::toString) + "⌫")
        }
        rows.forEachIndexed { index, values -> row(values, container, if (mode == "ko" && settings.layout == "moaki") MoakiLayout.weights(index) else null, alphabet = alphabet) }
        val info = currentInputEditorInfo
        val action = when (info?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)) {
            EditorInfo.IME_ACTION_SEARCH -> "검색"; EditorInfo.IME_ACTION_SEND -> "전송"; EditorInfo.IME_ACTION_DONE -> "완료"
            EditorInfo.IME_ACTION_GO -> "이동"; EditorInfo.IME_ACTION_NEXT -> "다음"; else -> "줄바꿈"
        }
        val bottom = LinearLayout(this).apply { isBaselineAligned = false }
        val bottomLabels = mutableListOf(if (mode in setOf("number", "symbol")) (if (settings.typingLanguage == "ko") "가나다" else "ABC") else "123", "이모지", "공백", action)
        if (alphabet) {
            bottomLabels.clear(); bottomLabels.addAll(listOf("!#1", "한/영", "?", "공백", ".", action))
        } else if (mode == "ko" && settings.layout == "moaki") {
            bottomLabels.clear(); bottomLabels.addAll(listOf("!#1", "한/영", ",", "공백", "ㅣ", action))
        } else if (settings.layout != "dubeol") bottomLabels.add(1, "한/영") // Moaki symbols and Cheonjiin need a language key too.
        bottomLabels.forEach { label ->
            val weight = if (alphabet) when (label) {
                "!#1" -> 1.3f; "공백" -> 4f; action -> 1.4f; else -> 1f
            } else if (mode == "ko" && settings.layout == "moaki") when(label) {
                "!#1" -> 1.4f; "공백" -> 4.5f; action -> 1.5f; else -> 1f
            } else if (label == "공백") 6f else if (label == "ㅣ") 1f else 1.5f
            val key = key(label, alphabet) {
                when (label) {
                    "123", "!#1" -> { finishComposition(); mode = "number"; renderKeys() }
                    "한/영" -> { finishComposition(); settings.typingLanguage = if (settings.typingLanguage == "ko") "en" else "ko"; mode = settings.typingLanguage; renderKeys() }
                    ",", "?", "." -> input(label)
                    "가나다", "ABC" -> { finishComposition(); mode = settings.typingLanguage; renderKeys() }
                    "공백" -> input(" ")
                    "이모지" -> showEmoji(true)
                    "ㅣ" -> input("ㅣ")
                    else -> enter()
                }
            }
            if (label == "이모지") { key.text = "☺"; (key as MoakiKeyButton).preferredTextSize = 25f; key.contentDescription = getString(R.string.emoji) }
            if (alphabet && label == "공백") {
                key.text = ""; key.contentDescription = getString(R.string.key_space)
                (key as MoakiKeyButton).centerIcon = KeyIcon(this, "space", AppUi.ink(this))
            }
            if (alphabet && label == "줄바꿈") { key.text = ""; (key as MoakiKeyButton).centerIcon = KeyIcon(this, "return", AppUi.ink(this)) }
            bottom.addView(key, LinearLayout.LayoutParams(0, dp(settings.keyHeight), weight))
            container.registerKey(key, regular = false, space = label == "공백", correctable = label == "ㅣ", clampRelease = label != "ㅣ")
            if (label == "ㅣ") {
                key.text = ""; (key as MoakiKeyButton).vowelCaption = getString(R.string.key_vowels)
                key.contentDescription = getString(R.string.key_vowels); moakiTouch(key, "")
            }
            if (label == "한/영") {
                key.text = if (alphabet) "" else "한/영"; (key as MoakiKeyButton).preferredTextSize = 13f
                key.languageSwitch = alphabet; key.contentDescription = getString(R.string.key_language)
                key.setOnLongClickListener { getSystemService(InputMethodManager::class.java).showInputMethodPicker(); true }
            }
            if (alphabet && label == "?") {
                (key as MoakiKeyButton).numberHint = "☺"
                key.tooltipText = getString(R.string.emoji); key.setOnLongClickListener { showEmoji(true); true }
            }
            if (alphabet && label == ".") key.setOnLongClickListener { alternatives(key, "."); true }
            if (label == ",") key.setOnLongClickListener { showEmoji(true); true }
        }
        container.addView(bottom)
    }
    private fun row(values: List<String>, container: LinearLayout, weights: List<Float>? = null,
                    height: Int = settings.keyHeight, alphabet: Boolean = false) {
        val inset = alphabet && values.size == 9 && values.firstOrNull() != "⇧"
        val row = LinearLayout(this).apply {
            // Keys share a frame center; text baselines vary with icons, hints and fitted labels.
            isBaselineAligned = false
            tag = height.toFloat() / settings.keyHeight
            if (!alphabet && values.size == 9 && values.firstOrNull() != "⇧") setPadding(dp(16), 0, dp(16), 0)
        }
        if (inset) row.addView(View(this), LinearLayout.LayoutParams(0, dp(height), .5f))
        values.forEachIndexed { index, value ->
            lateinit var key: Button
            key = key(value, alphabet) {
                when (value) {
                    "⌫" -> delete()
                    "⇧" -> {
                        val now = android.os.SystemClock.uptimeMillis()
                        if (mode == "en" && shift && now - shiftAt < 350) { caps = !caps; shift = caps } else { shift = !shift; caps = false }
                        shiftAt = now; updateLetterCase()
                    }
                    "기호" -> { finishComposition(); mode = "symbol"; renderKeys() }
                    "숫자" -> { finishComposition(); mode = "number"; renderKeys() }
                    else -> if (mode == "ko" && settings.layout == "cheonjiin" && value != ".") inputCheonjiin(value) else input(key.text.toString())
                }
            }
            row.addView(key, LinearLayout.LayoutParams(0, dp(height), weights?.get(index) ?: if (value in setOf("⇧", "⌫")) (if (alphabet) 1.4f else 1.3f) else 1f))
            val regular = value !in setOf("⇧", "⌫", "기호", "숫자") && !(mode == "ko" && settings.layout == "moaki")
            val moakiConsonant = mode == "ko" && settings.layout == "moaki" && value in MoakiLayout.consonants
            // Shift, delete and Moaki strokes own their touch streams; the rest are plain click keys.
            keys?.registerKey(key, regular, correctable = regular || moakiConsonant, clampRelease = !regular && !moakiConsonant && value !in setOf("⇧", "⌫"))
            if (value == "⇧") shiftKey = key
            if (value == "⇧") key.setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        shiftBeforePress = shift; capsBeforePress = caps; shiftHeld = true; shiftUsed = false
                        key.isPressed = true; key.performClick(); true
                    }
                    MotionEvent.ACTION_UP -> {
                        key.isPressed = false; shiftHeld = false
                        if (shiftUsed && !caps) { shift = false; updateLetterCase() }; true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        key.isPressed = false; shiftHeld = false
                        if (!shiftUsed) { shift = shiftBeforePress; caps = capsBeforePress }
                        else if (!caps) shift = false
                        updateLetterCase(); true
                    }
                    else -> true
                }
            }
            if (regular && alphabet && value.none(Char::isDigit)) letterKeys += key to value
            if (value == "⌫") {
                deleteRepeat(key)
            }
            else if (mode == "ko" && settings.layout == "moaki" && value in MoakiLayout.consonants) {
                (key as MoakiKeyButton).numberHint = MoakiLayout.numbers[value]
                moakiTouch(key, value)
            }
            // A hold only opens a picker when there is something to pick. Otherwise a slow,
            // deliberate press (for example every Hangul jamo) would type nothing.
            else if (value !in setOf("⇧", "기호", "숫자") && hasAlternatives(value)) key.setOnLongClickListener { alternatives(key, key.text.toString()); true }
        }
        if (inset) row.addView(View(this), LinearLayout.LayoutParams(0, dp(height), .5f))
        container.addView(row)
    }
    private fun updateLetterCase() {
        val normal = "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ"; val upper = "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ"
        for ((key, original) in letterKeys) {
            val value = if (mode == "en") { if (shift || caps) original.uppercase() else original.lowercase() }
                else {
                    val index = normal.indexOf(original).takeIf { it >= 0 } ?: upper.indexOf(original)
                    if (index >= 0) (if (shift) upper else normal)[index].toString() else original
                }
            if (key.text.toString() != value) { key.text = value; key.contentDescription = value }
        }
        shiftKey?.apply {
            (this as MoakiKeyButton).centerIcon = KeyIcon(this@KeyboardService, "shift", AppUi.ink(this@KeyboardService))
            invalidate()
            contentDescription = shiftDescription()
        }
    }
    private fun shiftDescription() = getString(if (caps) R.string.key_caps_on else if (shift) R.string.key_shift_on else R.string.key_shift)
    private fun keyFeedback(view: View) {
        if (settings.haptic) view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        if (settings.sound) getSystemService(AudioManager::class.java).playSoundEffect(AudioManager.FX_KEY_CLICK)
    }
    private fun moakiTouch(view: Button, base: String) {
        var gesture = MoakiGesture(dp(12).toDouble())
        var strokeThreshold = dp(12).toDouble()
        var originX = 0f; var originY = 0f; var active = false; var began = 0L; var moved = false
        view.tooltipText = getString(R.string.moaki_hint)
        fun preview() {
            val text = gesture.input(base)?.let { HangulComposer.compose(it.toList()) } ?: "—"
            val label = moakiPreview?.contentView as? TextView
            if (label != null) { label.text = text; return }
            val bubble = TextView(this).apply {
                this.text = text; textSize = 30f; gravity = Gravity.CENTER; includeFontPadding = false
                isSingleLine = true
                setAutoSizeTextTypeUniformWithConfiguration(12, 30, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
                setTextColor(AppUi.ink(this@KeyboardService)); background = AppUi.touchBackground(this@KeyboardService, AppUi.key(this@KeyboardService), 10)
            }
            val position = IntArray(2); view.getLocationOnScreen(position)
            moakiPreview = PopupWindow(bubble, dp(64), dp(52), false).apply {
                isTouchable = false; isClippingEnabled = true
                val left = (position[0] + view.width / 2 - dp(32)).coerceIn(0, (resources.displayMetrics.widthPixels - dp(64)).coerceAtLeast(0))
                // Anchor offsets stay in the IME window's coordinate space, including landscape.
                showAsDropDown(view, left - position[0], -view.height - dp(56), Gravity.LEFT)
            }
        }
        fun advance(event: MotionEvent) {
            if (kotlin.math.hypot(event.x - originX, event.y - originY) >= strokeThreshold) moved = true
            // Historical samples retain corners when Android batches fast moves.
            for (i in 0 until event.historySize) gesture.move((event.getHistoricalX(i) - originX).toDouble(), (event.getHistoricalY(i) - originY).toDouble())
            gesture.move((event.x - originX).toDouble(), (event.y - originY).toDouble())
            if (gesture.hasStroke) moved = true
        }
        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val density = resources.displayMetrics.density.toDouble()
                    strokeThreshold = MoakiGesture.activationDistance(view.width / density, view.height / density) * density
                    gesture = MoakiGesture(strokeThreshold); originX = event.x; originY = event.y; active = true; began = event.eventTime; moved = false
                    view.isPressed = true; preview(); true
                }
                MotionEvent.ACTION_MOVE -> { if (active) { advance(event); preview() }; true }
                MotionEvent.ACTION_UP -> {
                    if (active) {
                        advance(event); active = false; view.isPressed = false; moakiPreview?.dismiss(); moakiPreview = null
                        val number = MoakiLayout.numbers[base]?.takeIf { !moved && event.eventTime - began >= 450 }
                        (number ?: gesture.input(base))?.let { input(it) }
                    }; true
                }
                MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_DOWN -> {
                    active = false; view.isPressed = false; moakiPreview?.dismiss(); moakiPreview = null; true
                }
                else -> true
            }
        }
    }
    // IME keys deliberately use platform widgets with complete custom state and tint styling.
    @android.annotation.SuppressLint("AppCompatCustomView")
    private class MoakiKeyButton(context: android.content.Context) : Button(context) {
        var preferredTextSize = 19f
        var numberHint: String? = null
        var vowelCaption: String? = null
        var languageSwitch = false
        var centerIcon: android.graphics.drawable.Drawable? = null
        private val hintPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val density = resources.displayMetrics.density
            val availableWidth = (MeasureSpec.getSize(widthMeasureSpec) - 12f * density).coerceAtLeast(1f)
            val availableHeight = (MeasureSpec.getSize(heightMeasureSpec) - 10f * density).coerceAtLeast(1f)
            @Suppress("DEPRECATION")
            val preferredPixels = preferredTextSize * resources.displayMetrics.scaledDensity
            hintPaint.typeface = typeface; hintPaint.textSize = preferredPixels
            val measured = hintPaint.measureText(text.toString()).coerceAtLeast(1f)
            val pixels = minOf(preferredPixels, availableHeight * .85f, preferredPixels * availableWidth / measured)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, pixels)
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }
        @Suppress("DEPRECATION")
        override fun onDraw(canvas: android.graphics.Canvas) {
            val saved = canvas.save()
            super.onDraw(canvas)
            canvas.restoreToCount(saved)
            val overlay = canvas.save()
            // Single-line TextView scrolls its large text layout to center short labels.
            // Draw key overlays in visible view coordinates rather than that text layout.
            canvas.translate(scrollX.toFloat(), scrollY.toFloat())
            centerIcon?.let { icon ->
                val size = minOf((24 * resources.displayMetrics.density).toInt(), width - (12 * resources.displayMetrics.density).toInt(), height - (12 * resources.displayMetrics.density).toInt()).coerceAtLeast(1)
                val left = (width - size) / 2; val top = (height - size) / 2
                icon.setBounds(left, top, left + size, top + size); icon.draw(canvas)
            }
            if (languageSwitch) {
                hintPaint.color = currentTextColor; hintPaint.alpha = 255; hintPaint.typeface = typeface
                hintPaint.textSize = minOf(12f * resources.displayMetrics.scaledDensity, width * .32f)
                hintPaint.textAlign = android.graphics.Paint.Align.CENTER
                val center = (hintPaint.fontMetrics.ascent + hintPaint.fontMetrics.descent) / 2f
                canvas.drawText("한", width * .34f, height * .35f - center, hintPaint)
                canvas.drawText("영", width * .67f, height * .68f - center, hintPaint)
                hintPaint.strokeWidth = resources.displayMetrics.density
                canvas.drawLine(width * .33f, height * .72f, width * .68f, height * .28f, hintPaint)
            }
            vowelCaption?.let { caption ->
                hintPaint.color = currentTextColor; hintPaint.alpha = 255; hintPaint.textAlign = android.graphics.Paint.Align.CENTER
                hintPaint.typeface = typeface
                val density = resources.displayMetrics.density
                val availableWidth = (width - 10f * density).coerceAtLeast(1f)
                fun fit(value: String, size: Float): Float {
                    hintPaint.textSize = size * resources.displayMetrics.scaledDensity
                    return hintPaint.textSize * minOf(1f, availableWidth / hintPaint.measureText(value).coerceAtLeast(1f))
                }
                var topSize = fit("ㅣ·ㅡ", 12f); var captionSize = fit(caption, 10f)
                hintPaint.textSize = topSize; val topHeight = hintPaint.fontMetrics.let { it.descent - it.ascent }
                hintPaint.textSize = captionSize; val captionHeight = hintPaint.fontMetrics.let { it.descent - it.ascent }
                val gap = 2f * density
                val scale = minOf(1f, (height - 12f * density - gap).coerceAtLeast(1f) / (topHeight + captionHeight))
                topSize *= scale; captionSize *= scale
                val groupHeight = (topHeight + captionHeight) * scale + gap
                var top = (height - groupHeight) / 2f
                hintPaint.textSize = topSize
                canvas.drawText("ㅣ·ㅡ", width / 2f, top - hintPaint.fontMetrics.ascent, hintPaint)
                top += topHeight * scale + gap; hintPaint.textSize = captionSize
                canvas.drawText(caption, width / 2f, top - hintPaint.fontMetrics.ascent, hintPaint)
            }
            numberHint?.let {
                hintPaint.color = currentTextColor; hintPaint.alpha = 145; hintPaint.typeface = typeface
                val density = resources.displayMetrics.density
                hintPaint.textSize = minOf(10f * resources.displayMetrics.scaledDensity, (height - 10f * density) * .24f)
                hintPaint.textAlign = android.graphics.Paint.Align.RIGHT
                canvas.drawText(it, width - 8f * density, 7f * density - hintPaint.fontMetrics.ascent, hintPaint)
            }
            canvas.restoreToCount(overlay)
        }
    }
    private fun key(label: String, alphabet: Boolean = false, action: () -> Unit): Button = MoakiKeyButton(this).apply {
        val control = CONTROL_LABELS[label]?.let(::getString)
        text = control ?: label
        preferredTextSize = if (text.length > 2) 15f else 19f; isAllCaps = false
        gravity = Gravity.CENTER; includeFontPadding = false
        minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0; isSingleLine = true
        stateListAnimator = null; elevation = 0f; translationZ = 0f
        setPadding(dp(1), 0, dp(1), 0)
        val special = label != "공백" && (control != null || label in setOf("123", "!#1", "한/영", "⇧", "⌫", "가나다", "ABC") || label == "ㅣ" && !alphabet)
        val states = android.graphics.drawable.StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed), AppUi.rounded(this@KeyboardService, AppUi.pressedKey(this@KeyboardService), if (alphabet) 5 else 8))
            addState(intArrayOf(), AppUi.rounded(this@KeyboardService, if (special) AppUi.specialKey(this@KeyboardService) else AppUi.key(this@KeyboardService), if (alphabet) 5 else 8))
        }
        background = android.graphics.drawable.InsetDrawable(states, dp(3), dp(5), dp(3), dp(5))
        backgroundTintList = null; setTextColor(AppUi.ink(this@KeyboardService))
        typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        if (label in setOf("⇧", "⌫")) { text = ""; centerIcon = KeyIcon(this@KeyboardService, if (label == "⇧") "shift" else "delete", AppUi.ink(this@KeyboardService)) }
        contentDescription = when (label) { "⌫" -> getString(R.string.key_delete); "⇧" -> shiftDescription(); else -> text }
        setOnClickListener {
            // Keyboard keys already gave feedback on touch-down; popups and other buttons do it here.
            if (keys?.owns(this) != true) keyFeedback(this)
            action()
        }
    }
    private fun deleteRepeat(view: Button) {
        var downX = 0f; var repeats = 0; var started = 0L; var slideSteps = -1
        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x; slideSteps = -1; view.performClick(); stopDeleteRepeat()
                    repeats = 0; started = android.os.SystemClock.uptimeMillis()
                    // One character per repeat, two after 20 repeats, then a word every third repeat after 3 s.
                    repeatDelete = object : Runnable { override fun run() {
                        repeats++
                        when (val step = DeleteRepeat.step(repeats, android.os.SystemClock.uptimeMillis() - started)) {
                            is DeleteRepeat.Step.Characters -> repeat(step.count) { delete() }
                            DeleteRepeat.Step.Word -> if (repeats % 3 == 0) deleteWord()
                        }
                        handler.postDelayed(this, 65)
                    } }
                    handler.postDelayed(repeatDelete!!, 400); true
                }
                MotionEvent.ACTION_MOVE -> {
                    // HeliBoard's delete slider: sliding left selects one character per 10dp; lifting deletes it.
                    val steps = ((downX - event.x) / (DeleteRepeat.SLIDE_STEP_DP * resources.displayMetrics.density)).toInt().coerceAtLeast(0)
                    if (slideSteps < 0 && steps > 0 && !sensitive) { stopDeleteRepeat(); slideSteps = 0; beginDeleteSlide() }
                    if (slideSteps >= 0 && steps != slideSteps) {
                        slideSteps = steps; selectForDeleteSlide(steps)
                        if (settings.haptic) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> { stopDeleteRepeat(); if (slideSteps > 0) delete() else if (slideSteps == 0) selectForDeleteSlide(0); slideSteps = -1; true }
                MotionEvent.ACTION_CANCEL -> { stopDeleteRepeat(); if (slideSteps >= 0) selectForDeleteSlide(0); slideSteps = -1; true }
                else -> true
            }
        }
    }
    private var slideEnd = -1
    private var slideBefore = ""
    private fun beginDeleteSlide() {
        finishComposition(); keys?.resetPrediction()
        val connection = currentInputConnection
        slideEnd = if (selection.valid) selection.high else -1
        slideBefore = if (slideEnd >= 0) connection?.getTextBeforeCursor(256, 0)?.toString() ?: "" else ""
    }
    /** Selects the last [steps] characters before where the slide began; the host shows what will go. */
    private fun selectForDeleteSlide(steps: Int) {
        val connection = currentInputConnection ?: return
        if (slideEnd < 0) return
        var remaining = slideBefore; var length = 0
        repeat(steps) {
            val last = Unicode.previousLength(remaining)
            if (last > 0) { length += last; remaining = remaining.dropLast(last) }
        }
        val start = (slideEnd - length).coerceAtLeast(0)
        expectedWrite(Selection(start, slideEnd)) { connection.setSelection(start, slideEnd) }
    }
    /** Held delete past 3 seconds: the last word and the spaces after it. */
    private fun deleteWord() {
        finishComposition(); keys?.resetPrediction()
        val connection = currentInputConnection ?: return
        if (sensitive || !selection.collapsed) { delete(); return }
        val before = connection.getTextBeforeCursor(256, 0)?.toString() ?: return
        val word = DeleteRepeat.lastWord(before)
        if (word.isEmpty()) return
        val next = if (selection.low >= word.length) Selection(selection.low - word.length, selection.low - word.length) else null
        expectedWrite(next) { connection.deleteSurroundingText(word.length, 0) }
    }
    private fun stopDeleteRepeat() { repeatDelete?.let(handler::removeCallbacks); repeatDelete = null }
    private fun alternativeOptions(value: String) = when (value.lowercase()) {
        "a" -> listOf("á", "à", "â", "ä", "æ"); "e" -> listOf("é", "è", "ê", "ë"); "i" -> listOf("í", "ì", "î", "ï")
        "o" -> listOf("ó", "ò", "ô", "ö", "ø"); "u" -> listOf("ú", "ù", "û", "ü"); "$" -> listOf("₩", "€", "£", "¥")
        "." -> listOf(",", "…", "!", "?", ".com"); else -> if (mode == "ko" && settings.layout == "cheonjiin") value.map(Char::toString) else listOf(value)
    }
    private fun hasAlternatives(value: String) = alternativeOptions(value).size > 1
    private fun dismissAlternatives() { alternativesPopup?.dismiss(); alternativesPopup = null }
    private fun alternatives(anchor: View, value: String) {
        val options = alternativeOptions(value)
        dismissAlternatives()
        val row = LinearLayout(this).apply { isBaselineAligned = false }
        // Not focusable: a tap elsewhere reaches the keyboard and types its key, instead of
        // being spent on closing the picker.
        val popup = PopupWindow(row, LinearLayout.LayoutParams.WRAP_CONTENT, dp(settings.keyHeight), false)
        alternativesPopup = popup
        row.setBackgroundColor(AppUi.surface(this@KeyboardService))
        options.forEach { option -> row.addView(key(option) { finishComposition(); input(option); popup.dismiss() }, LinearLayout.LayoutParams(dp(48), -1)) }
        popup.elevation = dp(8).toFloat(); popup.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(AppUi.surface(this@KeyboardService)))
        popup.showAtLocation(anchor, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, 0, dp(settings.keyHeight * 2))
    }
    private fun isSensitive(info: EditorInfo?): Boolean =
        InputPrivacyPolicy.blocksEditor(info?.inputType, info?.imeOptions ?: 0, info?.hintText?.toString())
    /** Preserve every key row; reduce effective row height within display bounds. */
    private inner class BoundedKeyboardColumn : LinearLayout(this@KeyboardService) {
        private var routing = false
        /**
         * The window's side and bottom padding (navigation bar and cutout insets included) has no
         * view of its own, so presses there used to vanish. Hand them to the key rows, whose edge
         * keys own that strip.
         */
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            val keyboard = keys
            if (keyboard == null || keyboard.visibility != View.VISIBLE) { routing = false; return super.dispatchTouchEvent(event) }
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                val x = event.x; val y = event.y
                val insideKeys = x >= keyboard.left && x < keyboard.right && y >= keyboard.top && y < keyboard.bottom
                routing = !insideKeys && y >= keyboard.top
            }
            if (!routing) return super.dispatchTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) routing = false
            val dx = (scrollX - keyboard.left).toFloat(); val dy = (scrollY - keyboard.top).toFloat()
            event.offsetLocation(dx, dy)
            val handled = keyboard.dispatchTouchEvent(event)
            event.offsetLocation(-dx, -dy)
            return handled
        }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val displayHeight = if (Build.VERSION.SDK_INT >= 30)
                getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds.height()
            else resources.displayMetrics.heightPixels
            val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val parentLimit = MeasureSpec.getSize(heightMeasureSpec).takeIf {
                MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED && it > 0
            } ?: displayHeight
            val budget = minOf(parentLimit, (displayHeight * if (landscape) 0.65f else 0.50f).toInt(), dp(520)).coerceAtLeast(1)
            val keyboard = keys
            if (emojiVisible) emojiPanel?.let { emoji ->
                val height = minOf(emojiPreferredHeight, budget - paddingTop - paddingBottom).coerceAtLeast(1)
                if (emoji.layoutParams.height != height) emoji.layoutParams = emoji.layoutParams.apply { this.height = height }
            }
            if (keyboard != null && keyboard.visibility == View.VISIBLE && keyboard.childCount > 0) {
                val rows = keyboard.childCount
                val rowWeights = (0 until rows).map { (keyboard.getChildAt(it).tag as? Float) ?: 1f }
                val totalWeight = rowWeights.sum()
                val contentBudget = (budget - paddingTop - paddingBottom).coerceAtLeast(1)
                val stripHeight = if (strip?.visibility == View.VISIBLE) minOf(dp(STRIP_HEIGHT), contentBudget / (rows + 1)).coerceAtLeast(1) else 0
                strip?.let { if (it.layoutParams.height != stripHeight && stripHeight > 0) it.layoutParams = it.layoutParams.apply { height = stripHeight } }
                val desiredRowHeight = minOf(dp(settings.keyHeight), if (landscape) dp(42) else dp(64))
                val rowHeight = minOf(desiredRowHeight, ((contentBudget - stripHeight) / totalWeight).toInt()).coerceAtLeast(1)
                for (i in 0 until rows) {
                    val row = keyboard.getChildAt(i) as? LinearLayout ?: continue
                    val height = (rowHeight * rowWeights[i]).toInt().coerceAtLeast(1)
                    for (j in 0 until row.childCount) {
                        val child = row.getChildAt(j)
                        if (child.layoutParams.height != height) child.layoutParams = child.layoutParams.apply { this.height = height }
                    }
                }
            }
            super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(budget, MeasureSpec.AT_MOST))
        }
    }
    /** Whether the strip shows a chip at this point of the key column's top reach. */
    private fun stripClaims(x: Float, y: Float): Boolean {
        val bar = strip?.takeIf { it.isShown } ?: return false
        val column = keys ?: return false
        val from = IntArray(2); val to = IntArray(2); column.getLocationInWindow(from); bar.getLocationInWindow(to)
        fun claims(view: View, x: Float, y: Float): Boolean {
            if (!view.isShown || x < 0 || y < 0 || x >= view.width || y >= view.height) return false
            if (view is android.view.ViewGroup) for (index in view.childCount - 1 downTo 0) {
                val child = view.getChildAt(index)
                if (claims(child, x + view.scrollX - child.left, y + view.scrollY - child.top)) return true
            }
            return view is Button && view.isEnabled
        }
        return claims(bar, x + from[0] - to[0], y + from[1] - to[1])
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    companion object {
        /** dp above the top row, inside the strip's empty space, that still types the top-row key. */
        private const val TOP_ROW_REACH = 12
        private const val STRIP_HEIGHT = 44
        /** Internal key ids that show a localized label. */
        private val CONTROL_LABELS = mapOf("기호" to R.string.key_symbols, "숫자" to R.string.key_numbers, "검색" to R.string.key_search,
            "전송" to R.string.key_send, "완료" to R.string.key_done, "이동" to R.string.key_go, "다음" to R.string.key_next,
            "줄바꿈" to R.string.key_return, "공백" to R.string.key_space, "이모지" to R.string.emoji)
    }
}
