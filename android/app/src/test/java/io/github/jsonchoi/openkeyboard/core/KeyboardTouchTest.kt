package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class KeyboardTouchTest {
    private val keys = listOf(KeyboardTouchTarget(0, 0f, 0f, 40f, 44f), KeyboardTouchTarget(1, 46f, 0f, 40f, 44f), KeyboardTouchTarget(2, 92f, 0f, 40f, 44f, 0))
    @Test fun gapsAndBoundaryWobble() {
        assertEquals(0, KeyboardTouchTarget.resolve(42f, 20f, keys))
        assertEquals(0, KeyboardTouchTarget.resolve(44f, 20f, keys, 0, 1))
        assertEquals(1, KeyboardTouchTarget.resolve(53f, 20f, keys, 0, 1))
    }
    @Test fun controlsAndFarOutsideAreNeverTypedBySlidingLetters() {
        assertNull(KeyboardTouchTarget.resolve(110f, 20f, keys, 1, 1))
        assertNull(KeyboardTouchTarget.resolve(-30f, 20f, keys, 0, 1))
        assertNull(KeyboardTouchTarget.resolve(20f, 80f, keys, 0, 1))
    }
    @Test fun shortReleaseDriftKeepsTheTappedLetter() {
        // Onto a control, past the keyboard edge and below the row: the tap still types its letter.
        assertEquals(1, KeyboardTouchTarget.follow(100f, 20f, keys, 1, 1))
        assertEquals(0, KeyboardTouchTarget.follow(-14f, 20f, keys, 0, 1))
        assertEquals(0, KeyboardTouchTarget.follow(20f, 60f, keys, 0, 1))
        assertEquals(0, KeyboardTouchTarget.follow(21f, 60f, keys, 0, 1, unit = 1.5f))
        // Letters still switch on a real slide, and a deliberate slide away still cancels.
        assertEquals(1, KeyboardTouchTarget.follow(53f, 20f, keys, 0, 1))
        assertNull(KeyboardTouchTarget.follow(110f, 20f, keys, 1, 1))
        assertNull(KeyboardTouchTarget.follow(20f, 80f, keys, 0, 1))
        assertNull(KeyboardTouchTarget.follow(100f, 20f, keys, null, 1))
        assertNull(KeyboardTouchTarget.follow(Float.NaN, 20f, keys, 0, 1))
    }
    @Test fun outOfOrderReleaseTypesInPressOrderOnce() {
        val sequence = KeyboardTouchSequence(); sequence.begin(7, 0); sequence.begin(3, 1)
        assertEquals(listOf(0, 1), sequence.end(3).map { it.key }); assertTrue(sequence.end(7).isEmpty())
    }
    @Test fun twoFingersOnSameKeyAndReusedPointer() {
        val sequence = KeyboardTouchSequence(); sequence.begin(2, 0); sequence.begin(9, 0)
        assertEquals(listOf(0, 0), sequence.end(9).map { it.key }); sequence.begin(2, 1)
        assertEquals(listOf(1), sequence.end(2).map { it.key })
    }
    @Test fun slidesAndCancellation() {
        val sequence = KeyboardTouchSequence(); sequence.begin(0, 0); sequence.move(0, 1)
        assertEquals(listOf(1), sequence.end(0).map { it.key }); sequence.begin(4, 0); sequence.cancel(4)
        assertTrue(sequence.end(4).isEmpty()); sequence.begin(8, 1); sequence.cancelAll(); assertTrue(sequence.end(8).isEmpty())
    }
    @Test fun leavingAndReentering() {
        val sequence = KeyboardTouchSequence(); sequence.begin(0, 0); sequence.move(0, null)
        assertTrue(sequence.pressedKeys.isEmpty()); sequence.move(0, 1)
        assertEquals(listOf(1), sequence.end(0).map { it.key })
    }
    @Test fun consumedGestureFlushesOlderLetterOnly() {
        val sequence = KeyboardTouchSequence(); sequence.begin(0, 0); sequence.begin(1, 5); sequence.move(1, null)
        assertEquals(listOf(0), sequence.end(1).map { it.key }); assertTrue(sequence.end(0).isEmpty())
    }
    @Test fun modifierFlushDoesNotDuplicateLaterFingerRelease() {
        val sequence = KeyboardTouchSequence(); sequence.begin(0, 0); sequence.begin(1, 1)
        assertEquals(listOf(0, 1), sequence.flush().map { it.key })
        assertTrue(sequence.end(0).isEmpty()); assertTrue(sequence.end(1).isEmpty())
    }
    @Test fun quickSpaceSwipeAndVerticalMovementAreNotCursorGestures() {
        val gesture = KeyboardCursorGesture()
        assertEquals(0, gesture.update(50f, 0f, 100)); assertFalse(gesture.active)
        assertEquals(0, gesture.update(5f, 30f, 500)); assertFalse(gesture.active)
    }
    @Test fun cursorStepBoundaryHasNoBackAndForthJitter() {
        val gesture = KeyboardCursorGesture()
        assertEquals(1, gesture.update(36f, 0f, 300)); assertTrue(gesture.active)
        for (x in listOf(35.9f, 36.1f, 35f, 37f)) assertEquals(0, gesture.update(x, 0f, 350))
        assertEquals(-1, gesture.update(24f, 0f, 400)); assertEquals(-2, gesture.update(0f, 0f, 450))
    }
}
