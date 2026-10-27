package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class KeyboardSelectionTrackerTest {
    private fun caret(at: Int) = Selection(at, at)
    @Test fun delayedUpdatesCannotRollBackTheLatestPredictedCursor() {
        val tracker = KeyboardSelectionTracker(); tracker.reset(caret(0))
        for (position in 1..3) tracker.expect(caret(position))
        assertTrue(tracker.acknowledge(caret(0), caret(1))); assertEquals(caret(3), tracker.selection)
        assertTrue(tracker.acknowledge(caret(1), caret(2))); assertEquals(caret(3), tracker.selection)
        assertTrue(tracker.acknowledge(caret(2), caret(3))); assertEquals(caret(3), tracker.selection)
        assertFalse(tracker.acknowledge(caret(3), caret(1))); assertEquals(caret(1), tracker.selection)
    }
    @Test fun coalescedAckAndExplicitMoveToAnOlderPendingPosition() {
        val tracker = KeyboardSelectionTracker(); tracker.reset(caret(0))
        for (position in 1..3) tracker.expect(caret(position))
        assertFalse(tracker.acknowledge(caret(3), caret(1))); assertEquals(caret(1), tracker.selection)
        for (position in 2..4) tracker.expect(caret(position))
        assertTrue(tracker.acknowledge(caret(1), caret(4))); assertEquals(caret(4), tracker.selection)
        assertFalse(tracker.acknowledge(caret(4), Selection(1, 3))); assertEquals(Selection(1, 3), tracker.selection)
    }
    @Test fun replacingTheComposingSyllableAtTheSameCaretIsAcknowledged() {
        val tracker = KeyboardSelectionTracker(); tracker.reset(caret(0))
        repeat(3) { tracker.expect(caret(1)) }
        assertTrue(tracker.acknowledge(caret(0), caret(1))); assertEquals(caret(1), tracker.selection)
        tracker.reset(caret(9)); assertFalse(tracker.acknowledge(caret(9), caret(1)))
        assertFalse("An idle callback can cancel composing text without moving the caret", tracker.acknowledge(caret(1), caret(1)))
    }
    @Test fun backgroundPreviewReadsDoNotErasePendingAcknowledgements() {
        val tracker = KeyboardSelectionTracker(); tracker.reset(caret(0))
        for (position in 1..3) tracker.expect(caret(position))
        tracker.observe(caret(3)); tracker.observe(caret(2))
        assertEquals(caret(3), tracker.selection)
        assertTrue(tracker.acknowledge(caret(0), caret(1))); assertEquals(caret(3), tracker.selection)
        tracker.observe(caret(8)); assertEquals(caret(8), tracker.selection)
        assertFalse(tracker.acknowledge(caret(8), caret(1)))
    }
}
