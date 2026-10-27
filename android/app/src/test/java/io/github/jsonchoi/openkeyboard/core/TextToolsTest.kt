package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class TextToolsTest {
    private val chars: (String) -> List<String> = { it.map(Char::toString) }
    private val shortcuts = listOf(TextShortcut("ㅂㄱ", "반갑습니다"), TextShortcut("주소", "서울시 중구 세종대로 110"))
    @Test fun shortcutMatchesOnlyTheWholeLastWord() {
        assertEquals("반갑습니다", TextShortcuts.match("안녕하세요 ㅂㄱ", shortcuts)?.expansion)
        assertEquals("반갑습니다", TextShortcuts.match("ㅂㄱ", shortcuts)?.expansion)
        assertNull(TextShortcuts.match("ㅂㅂㄱ", shortcuts))
        assertNull(TextShortcuts.match("ㅂㄱ ", shortcuts))
        assertNull(TextShortcuts.match("", shortcuts))
        assertEquals("주소", TextShortcuts.match("우리\n주소", shortcuts)?.trigger)
    }
    @Test fun shortcutValidationRejectsUnsafeEntries() {
        assertNull(TextShortcuts.validate("ㄱㅅ", "감사합니다", shortcuts, chars))
        assertEquals(TextError.TRIGGER_SPACE, TextShortcuts.validate("ㄱ ㅅ", "감사합니다", shortcuts, chars))
        assertEquals(TextError.DUPLICATE, TextShortcuts.validate("ㅂㄱ", "또", shortcuts, chars))
        assertNull(TextShortcuts.validate("ㅂㄱ", "반가워요", shortcuts, chars, replacing = "ㅂㄱ"))
        assertEquals(TextError.TRIGGER_LONG, TextShortcuts.validate("a".repeat(21), "x", shortcuts, chars))
        assertEquals(TextError.TEXT_LENGTH, TextShortcuts.validate("ㄱ", " ", shortcuts, chars))
        assertEquals(TextError.SAME, TextShortcuts.validate("ㄱ", "ㄱ", shortcuts, chars))
        assertEquals(TextError.FULL, TextShortcuts.validate("ㄱ", "x", List(300) { TextShortcut("t$it", "x") }, chars))
    }
    @Test fun snippetValidationLimitsCountAndDuplicates() {
        assertNull(Snippets.validate("늦어서 죄송합니다", emptyList(), chars))
        assertEquals(TextError.DUPLICATE, Snippets.validate("a", listOf("a"), chars))
        assertNull(Snippets.validate("a", listOf("a"), chars, replacing = "a"))
        assertEquals(TextError.TEXT_LENGTH, Snippets.validate("   ", emptyList(), chars))
        assertEquals(TextError.TEXT_LENGTH, Snippets.validate("x".repeat(501), emptyList(), chars))
        assertEquals(TextError.FULL, Snippets.validate("b", List(50) { "s$it" }, chars))
    }
}
