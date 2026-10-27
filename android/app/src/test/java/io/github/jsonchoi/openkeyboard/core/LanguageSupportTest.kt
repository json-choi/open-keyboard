package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class LanguageSupportTest {
    @Test fun firstKoreanOrEnglishDeviceLanguageWins() {
        assertEquals("ko", LanguageSupport.typingLanguage(listOf("ko-KR")))
        assertEquals("ko", LanguageSupport.typingLanguage(listOf("ko_KR")))
        assertEquals("en", LanguageSupport.typingLanguage(listOf("en-GB", "ko-KR")))
        assertEquals("ko", LanguageSupport.typingLanguage(listOf("ja-JP", "ko-KR")))
        assertEquals("en", LanguageSupport.typingLanguage(listOf("ja-JP")))
        assertEquals("en", LanguageSupport.typingLanguage(emptyList()))
    }
}
