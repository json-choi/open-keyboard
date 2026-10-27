package io.github.jsonchoi.openkeyboard.core

data class TextShortcut(val trigger: String, val expansion: String)

/** Local text replacement. Matching reads only the word before the cursor and never leaves the device. */
object TextShortcuts {
    const val MAX_COUNT = 300
    const val MAX_TRIGGER = 20
    const val MAX_EXPANSION = 500
    /** Returns why the entry cannot be saved, or null when it can. */
    fun validate(trigger: String, expansion: String, existing: List<TextShortcut>, graphemes: (String) -> List<String>, replacing: String? = null): TextError? = when {
        trigger.isEmpty() || trigger.any(Char::isWhitespace) -> TextError.TRIGGER_SPACE
        graphemes(trigger).size > MAX_TRIGGER -> TextError.TRIGGER_LONG
        expansion.isBlank() || graphemes(expansion).size > MAX_EXPANSION -> TextError.TEXT_LENGTH
        trigger == expansion -> TextError.SAME
        existing.any { it.trigger == trigger && it.trigger != replacing } -> TextError.DUPLICATE
        replacing == null && existing.size >= MAX_COUNT -> TextError.FULL
        else -> null
    }
    /** The trigger must be the whole last word: "ㅂㄱ" matches "안녕 ㅂㄱ" but not "ㅂㅂㄱ". */
    fun match(before: String, shortcuts: List<TextShortcut>): TextShortcut? {
        if (before.isEmpty() || before.last().isWhitespace()) return null
        val word = before.substring(before.indexOfLast(Char::isWhitespace) + 1)
        return shortcuts.firstOrNull { it.trigger == word }
    }
}

/** Saved phrases the user inserts with one tap from the strip above the keys. */
object Snippets {
    const val MAX_COUNT = 50
    const val MAX_LENGTH = 500
    fun validate(value: String, existing: List<String>, graphemes: (String) -> List<String>, replacing: String? = null): TextError? = when {
        value.isBlank() || graphemes(value).size > MAX_LENGTH -> TextError.TEXT_LENGTH
        existing.any { it == value && it != replacing } -> TextError.DUPLICATE
        replacing == null && existing.size >= MAX_COUNT -> TextError.FULL
        else -> null
    }
}

/** Validation failures; the app maps each to a localized string. */
enum class TextError { TRIGGER_SPACE, TRIGGER_LONG, TEXT_LENGTH, SAME, DUPLICATE, FULL }
