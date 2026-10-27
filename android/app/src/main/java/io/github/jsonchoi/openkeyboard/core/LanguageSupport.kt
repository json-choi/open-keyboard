package io.github.jsonchoi.openkeyboard.core

import java.util.Locale

/** The keyboard types Korean or English; the first of those in the device's language list wins. */
object LanguageSupport {
    val typingLanguages = listOf("ko", "en")
    fun typingLanguage(preferred: List<String>): String =
        preferred.map { Locale.forLanguageTag(it.replace('_', '-')).language }.firstOrNull { it in typingLanguages } ?: "en"
}
