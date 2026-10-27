package io.github.jsonchoi.openkeyboard.core

/** Familiar Moaki grid: narrow punctuation columns and number holds on the middle rows. */
object MoakiLayout {
    val rows = listOf(listOf("~", "ㅃ", "ㅉ", "ㄸ", "ㄲ", "ㅆ", "!"),
        listOf("^", "ㅂ", "ㅈ", "ㄷ", "ㄱ", "ㅅ", "?"),
        listOf(";", "ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "."),
        listOf("*", "ㅋ", "ㅌ", "ㅊ", "ㅍ", "⌫"))
    val consonants = "ㅃㅉㄸㄲㅆㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎㅋㅌㅊㅍ".map(Char::toString).toSet()
    val numbers = "ㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎ".map(Char::toString).zip("1234567890".map(Char::toString)).toMap()
    fun weights(row: Int) = if (row == 3) listOf(.6f, 1f, 1f, 1f, 1f, 1.6f) else listOf(.6f, 1f, 1f, 1f, 1f, 1f, .6f)
}
