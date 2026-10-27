package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class HangulComposerTest {
    private fun composed(strokes: String) = HangulComposer.compose(strokes.toList())
    @Test fun dailyKoreanPhrases() {
        assertEquals("한글", composed("ㅎㅏㄴㄱㅡㄹ"))
        assertEquals("안녕하세요", composed("ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ"))
        assertEquals("읽다", composed("ㅇㅣㄹㄱㄷㅏ"))
        assertEquals("값이", composed("ㄱㅏㅂㅅㅇㅣ"))
        assertEquals("가시", composed("ㄱㅏㅅㅣ"))
        assertEquals("갈가", composed("ㄱㅏㄹㄱㅏ"))
        assertEquals("괜찮아요", composed("ㄱㅗㅐㄴㅊㅏㄴㅎㅇㅏㅇㅛ"))
        assertEquals("똠방각하", composed("ㄸㅗㅁㅂㅏㅇㄱㅏㄱㅎㅏ"))
    }
    @Test fun everyModernSyllable() {
        val initials = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
        val vowels = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
        val finals = "\u0000ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"
        val split = mapOf('ㄳ' to "ㄱㅅ", 'ㄵ' to "ㄴㅈ", 'ㄶ' to "ㄴㅎ", 'ㄺ' to "ㄹㄱ", 'ㄻ' to "ㄹㅁ", 'ㄼ' to "ㄹㅂ", 'ㄽ' to "ㄹㅅ", 'ㄾ' to "ㄹㅌ", 'ㄿ' to "ㄹㅍ", 'ㅀ' to "ㄹㅎ", 'ㅄ' to "ㅂㅅ")
        initials.forEachIndexed { l, initial -> vowels.forEachIndexed { v, vowel -> finals.forEachIndexed { t, final ->
            val suffix = if (t == 0) "" else split[final] ?: final.toString()
            val expected = (0xAC00 + (l * 21 + v) * 28 + t).toChar().toString()
            assertEquals("$initial$vowel$suffix", expected, composed("$initial$vowel$suffix"))
        } } }
    }
    @Test fun deletionReversesPhysicalStrokes() {
        val composer = HangulComposer()
        "ㄱㅗㅏㄴ".forEach(composer::input)
        assertEquals("관", composer.text)
        assertEquals("과", composer.backspace())
        assertEquals("고", composer.backspace())
        assertEquals("ㄱ", composer.backspace())
        assertEquals("", composer.backspace())
        assertEquals("", composer.backspace())
    }
    @Test fun isolatedJamoAndWordBreaks() {
        assertEquals("ㅏㄸㅋㅋ", composed("ㅏㄸㅋㅋ"))
        assertEquals("한 글!", composed("ㅎㅏㄴ ㄱㅡㄹ!"))
    }
    @Test fun cheonjiinVowels() {
        val cases = mapOf("ㅣㆍ" to "ㅏ", "ㅣㆍㅣ" to "ㅐ", "ㅣㆍㆍ" to "ㅑ", "ㅣㆍㆍㅣ" to "ㅒ", "ㆍㅣ" to "ㅓ",
            "ㆍㅣㅣ" to "ㅔ", "ㆍㆍㅣ" to "ㅕ", "ㆍㆍㅣㅣ" to "ㅖ", "ㆍㅡ" to "ㅗ", "ㆍㅡㅣㆍ" to "ㅘ",
            "ㆍㅡㅣㆍㅣ" to "ㅙ", "ㆍㅡㅣ" to "ㅚ", "ㆍㆍㅡ" to "ㅛ", "ㅡㆍ" to "ㅜ", "ㅡㆍㆍㅣ" to "ㅝ",
            "ㅡㆍㆍㅣㅣ" to "ㅞ", "ㅡㆍㅣ" to "ㅟ", "ㅡㆍㆍ" to "ㅠ", "ㅡ" to "ㅡ", "ㅡㅣ" to "ㅢ", "ㅣ" to "ㅣ")
        cases.forEach { (strokes, expected) -> assertEquals(strokes, expected, CheonjiinComposer.normalize(strokes.toList()).joinToString("")) }
    }
    @Test fun cheonjiinCycleTimeoutAndDelete() {
        val c = CheonjiinComposer()
        assertEquals("ㄱ", c.consonant("ㄱㅋㄲ", 1000))
        assertEquals("ㅋ", c.consonant("ㄱㅋㄲ", 1100))
        assertEquals("ㄲ", c.consonant("ㄱㅋㄲ", 1200))
        c.vowel('ㅣ'); c.vowel('ㆍ'); assertEquals("까", c.text)
        assertEquals("깡", c.consonant("ㅇㅁ", 1300))
        assertEquals("까", c.backspace())
        assertEquals("끼", c.backspace())
        assertEquals("ㄲ", c.backspace())
        c.clear()
        assertEquals("ㄱ", c.consonant("ㄱㅋㄲ", 2000))
        assertEquals("ㄱㄱ", c.consonant("ㄱㅋㄲ", 2700))
    }
}
