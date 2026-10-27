package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class MoakiGestureTest {
    @org.junit.Test fun referenceLayoutKeepsNarrowPunctuationAndNumberHints() {
        org.junit.Assert.assertEquals(listOf(7, 7, 7, 6), MoakiLayout.rows.map { it.size })
        org.junit.Assert.assertEquals(listOf("~", "ㅃ", "ㅉ", "ㄸ", "ㄲ", "ㅆ", "!"), MoakiLayout.rows.first())
        org.junit.Assert.assertEquals(listOf("*", "ㅋ", "ㅌ", "ㅊ", "ㅍ", "⌫"), MoakiLayout.rows.last())
        org.junit.Assert.assertEquals("1", MoakiLayout.numbers["ㅂ"]); org.junit.Assert.assertEquals("0", MoakiLayout.numbers["ㅎ"])
        org.junit.Assert.assertEquals(19, MoakiLayout.consonants.size)
        org.junit.Assert.assertEquals(MoakiLayout.consonants, MoakiLayout.rows.flatten().toSet().intersect(MoakiLayout.consonants))
        for (row in 0..3) org.junit.Assert.assertEquals(6.2f, MoakiLayout.weights(row).sum(), .001f)
    }

    private fun gesture(directions: String): MoakiGesture {
        val gesture = MoakiGesture(); var x = 0.0; var y = 0.0
        directions.forEach {
            val delta = when(it) { 'R' -> 40 to 0; 'L' -> -40 to 0; 'U' -> 0 to -40; 'D' -> 0 to 40; 'I' -> 40 to -40; else -> 40 to 40 }
            x += delta.first; y += delta.second; gesture.move(x, y)
        }
        return gesture
    }
    private val paths = listOf("R","RL","RLR","RLRL","L","LR","LRL","LRLR","U","UR","URL","UD","UDU","D","DL","DLR","DU","DUD","E","EI","I")
    @Test fun everyVowelAndMirroredDiagonals() {
        paths.zip("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".toList()).forEach { (path, expected) ->
            assertEquals(path, "ㄱ$expected", gesture(path).input("ㄱ")); assertEquals(expected.toString(), gesture(path).input(""))
        }
        val left = MoakiGesture(); left.move(-40.0, -40.0); assertEquals('ㅣ', left.vowel)
        val down = MoakiGesture(); down.move(-40.0, 40.0); down.move(0.0, 0.0); assertEquals('ㅢ', down.vowel)
    }
    @Test fun tapJitterLongStrokesAndInvalidPaths() {
        val tap = MoakiGesture(); tap.move(5.0, -3.0); tap.move(-4.0, 2.0)
        assertEquals("ㄲ", tap.input("ㄲ")); assertEquals("ㅣ", tap.input(""))
        assertEquals("ㄱㅏ", gesture("RRRR").input("ㄱ"))
        assertNull(gesture("RU").input("ㄱ")); assertNull(gesture("RLRLRLRLRL").input("ㄱ"))
    }
    @Test fun allInitialsComposeWithAllGestureVowels() {
        "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".forEachIndexed { initial, char -> paths.forEachIndexed { vowel, path ->
            assertEquals((0xAC00 + (initial * 21 + vowel) * 28).toChar().toString(), HangulComposer.compose(gesture(path).input(char.toString())!!.toList()))
        } }
    }
    @Test fun phraseFinalsSpaceAndDeletion() {
        val composer = HangulComposer()
        listOf("ㅇㅏ", "ㄴ", "ㄴㅕ", "ㅇ", "ㅎㅏ", "ㅅㅔ", "ㅇㅛ").forEach { input -> input.forEach { composer.input(it) } }
        assertEquals("안녕하세요", composer.text)
        assertEquals("안녕하셍", composer.backspace()); assertEquals("안녕하세", composer.backspace())
        composer.clear(); "ㄱㅏㅂㅅㅇㅣ".forEach { composer.input(it) }; assertEquals("값이", composer.text)
    }
    @Test fun roundedCornerRecoversWithoutDroppingTheVowel() {
        val rounded = MoakiGesture()
        listOf(0.0 to -24.0, 8.0 to -32.0, 10.0 to -34.0, 24.0 to -34.0).forEach { (x, y) -> rounded.move(x, y) }
        assertEquals("ㄱㅘ", rounded.input("ㄱ"))
        val unfinished = MoakiGesture(); unfinished.move(0.0, -24.0); unfinished.move(10.0, -34.0)
        assertEquals("ㄱㅗ", unfinished.input("ㄱ"))
    }
    @Test fun smallTerminalWobbleKeepsVowelButSustainedWrongTurnsFail() {
        val wobble = MoakiGesture(); wobble.move(24.0, 0.0); wobble.move(34.0, -10.0)
        assertEquals("ㄱㅏ", wobble.input("ㄱ")); wobble.move(34.0, -24.0); assertNull(wobble.input("ㄱ"))
        val wrong = MoakiGesture(); wrong.move(24.0, 0.0)
        for (y in listOf(12.0, 24.0, 36.0)) wrong.move(24.0, -y)
        assertNull(wrong.input("ㄱ"))
    }
    @Test fun activationDistanceScalesAndClampsToKeySize() {
        assertEquals(8.0, MoakiGesture.activationDistance(32.0, 32.0), 0.001)
        assertEquals(10.56, MoakiGesture.activationDistance(48.0, 44.0), 0.001)
        assertEquals(16.0, MoakiGesture.activationDistance(100.0, 100.0), 0.001)
        assertEquals(12.0, MoakiGesture.activationDistance(Double.NaN, 44.0), 0.001)
    }
}
