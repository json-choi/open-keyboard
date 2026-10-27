package io.github.jsonchoi.openkeyboard

import android.icu.text.BreakIterator
import java.util.Locale

/** User-perceived characters, so delete and cursor moves never split an emoji or a Hangul cluster. */
object Unicode {
    fun graphemes(text: String): List<String> {
        val result = mutableListOf<String>()
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(text) }
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) { result += text.substring(start, end); start = end; end = iterator.next() }
        return result
    }
    fun previousLength(text: String): Int = graphemes(text).lastOrNull()?.length ?: 0
    fun nextLength(text: String): Int = graphemes(text).firstOrNull()?.length ?: 0
}
