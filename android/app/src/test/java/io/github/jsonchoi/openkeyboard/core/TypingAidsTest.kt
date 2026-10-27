package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TypingAidsTest {
    @Test fun tapPredictionFollowsTheHangulAutomaton() {
        val prediction = KoreanTapPrediction()
        assertNull("Any key can start a word", prediction.reach("ㅎ"))
        prediction.record("ㅎ")
        assertEquals("An onset wants a vowel", KeyboardTouchTarget.MAX_REACH, prediction.reach("ㅗ")!!, 1e-6f)
        assertEquals(0f, prediction.reach("ㅅ")!!, 1e-6f)
        prediction.record("ㅗ")
        assertTrue("ㅗ can become ㅘ ㅙ ㅚ", prediction.reach("ㅏ")!! > prediction.reach("ㅓ")!!)
        assertTrue("…or take a final", prediction.reach("ㄴ")!! > prediction.reach("ㅛ")!!)
        prediction.record("ㅏ")
        assertTrue("화 is followed by a consonant", prediction.reach("ㄴ")!! > prediction.reach("ㅣ")!!)
        prediction.record("ㄹ")
        val open = KoreanTapPrediction.KEYS.map { prediction.reach(it.toString())!! }
        assertTrue("After 활 a vowel, a second final or a new syllable are all plausible", open.max() - open.min() < 0.05f)
        prediction.record(" "); assertNull(prediction.reach("ㅎ"))
        prediction.record("ㅉ"); assertNull("Not a dubeolsik key", prediction.reach("1"))
        assertEquals(KeyboardTouchTarget.MAX_REACH, prediction.reach("ㅏ")!!, 1e-6f)
        prediction.reset(); assertNull(prediction.reach("ㅏ"))
    }
    @Test fun likelyKeyTakesAtMostAQuarterAndNeverTheMiddle() {
        val keys = listOf(KeyboardTouchTarget(0, 0f, 0f, 100f, 120f), KeyboardTouchTarget(1, 100f, 0f, 100f, 120f), KeyboardTouchTarget(2, 200f, 0f, 100f, 120f, 0))
        val vowel = mapOf(0 to 0f, 1 to KeyboardTouchTarget.MAX_REACH)
        assertEquals(0, KeyboardTouchTarget.resolve(95f, 60f, keys))
        assertEquals(1, KeyboardTouchTarget.resolve(95f, 60f, keys, reach = vowel))
        assertEquals(1, KeyboardTouchTarget.resolve(76f, 60f, keys, reach = vowel))
        assertEquals(0, KeyboardTouchTarget.resolve(74f, 60f, keys, reach = vowel))
        assertEquals(0, KeyboardTouchTarget.resolve(50f, 5f, keys, reach = vowel))
        assertEquals(1, KeyboardTouchTarget.follow(95f, 60f, keys, current = 1, reach = vowel))
        assertEquals("Equal reach keeps the drawn boundary", 0, KeyboardTouchTarget.resolve(99f, 60f, keys, reach = mapOf(0 to 0.2f, 1 to 0.2f)))
        assertEquals("Controls never shrink", 2, KeyboardTouchTarget.resolve(201f, 60f, keys, reach = mapOf(1 to KeyboardTouchTarget.MAX_REACH)))
        assertEquals("Reach is capped", 0, KeyboardTouchTarget.resolve(74f, 60f, keys, reach = mapOf(0 to 0f, 1 to 9f)))
        val stacked = listOf(KeyboardTouchTarget(0, 0f, 0f, 100f, 120f), KeyboardTouchTarget(1, 0f, 120f, 100f, 120f, row = 1))
        val below = mapOf(0 to 0f, 1 to KeyboardTouchTarget.MAX_REACH)
        assertEquals("Rows trade half as much height", 1, KeyboardTouchTarget.resolve(50f, 106f, stacked, reach = below))
        assertEquals(0, KeyboardTouchTarget.resolve(50f, 104f, stacked, reach = below))
    }
    @Test fun everyPointOfADubeolsikKeyboardTypesAKeyAndKeyCentresHold() {
        // iPhone-sized dubeolsik rows: 6pt gaps between keys and 10pt between rows, as drawn on iOS.
        val keys = mutableListOf<KeyboardTouchTarget>(); val values = mutableListOf<String?>()
        fun row(y: Float, left: Float, width: Float, labels: List<String?>, weights: List<Float>) {
            val unit = (width - 6 * (labels.size - 1)) / weights.sum(); var x = left
            labels.forEachIndexed { index, label ->
                keys += KeyboardTouchTarget(keys.size, x, y, unit * weights[index], 44f, if (label == null) 0 else 1, (y / 54).toInt())
                values += label; x += unit * weights[index] + 6
            }
        }
        row(0f, 0f, 380f, "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ".map(Char::toString), List(10) { 1f })
        row(54f, 19f, 342f, "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".map(Char::toString), List(9) { 1f })
        row(108f, 0f, 380f, listOf(null) + "ㅋㅌㅊㅍㅠㅜㅡ".map(Char::toString) + listOf(null), listOf(1.4f) + List(7) { 1f } + listOf(1.4f))
        row(162f, 0f, 380f, listOf(null, null, null, null), listOf(1.3f, 1f, 6f, 1.4f))
        // Edge keys own the inset beside them, as both apps extend them.
        keys[10] = keys[10].copy(x = 0f, width = keys[10].x + keys[10].width); keys[18] = keys[18].copy(width = 380f - keys[18].x)
        val prediction = KoreanTapPrediction()
        val contexts = listOf("", "ㅎ", "ㅎㅗ", "ㅎㅗㅏ", "ㅎㅗㅏㄹ", "ㄷㅏㄹㄱ", "ㅋ", "ㅇㅡ")
        for (context in contexts) {
            prediction.reset(); context.forEach { prediction.record(it.toString()) }
            val reach = values.withIndex().mapNotNull { (id, value) -> value?.let { prediction.reach(it) }?.let { id to it } }.toMap()
            var y = -8f
            while (y <= 214f) {
                var x = -8f
                while (x <= 388f) { assertNotNull("$context ($x, $y)", KeyboardTouchTarget.resolve(x, y, keys, reach = reach)); x += 1f }
                y += 1f
            }
            for (key in keys) {
                // The middle half of the width and the middle three quarters of the height always type the key.
                for (fx in listOf(.25f, .5f, .75f)) for (fy in listOf(.125f, .5f, .875f))
                    assertEquals("$context ${values[key.id]}", key.id, KeyboardTouchTarget.resolve(key.x + key.width * fx, key.y + key.height * fy, keys, reach = reach))
            }
        }
    }
    @Test fun deleteRepeatAcceleratesThenDeletesWords() {
        assertEquals(DeleteRepeat.Step.Characters(1), DeleteRepeat.step(1, 500))
        assertEquals(DeleteRepeat.Step.Characters(2), DeleteRepeat.step(21, 2000))
        assertEquals(DeleteRepeat.Step.Word, DeleteRepeat.step(30, 3100))
        assertEquals("반갑습니다  ", DeleteRepeat.lastWord("안녕하세요 반갑습니다  "))
        assertEquals("정말!", DeleteRepeat.lastWord("좋아요, 정말!"))
        assertEquals("가족", DeleteRepeat.lastWord("👨‍👩‍👧‍👦 가족"))
        assertEquals("", DeleteRepeat.lastWord(""))
    }
}
