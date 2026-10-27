package io.github.jsonchoi.openkeyboard.core

/** Separates delayed acknowledgements of IME writes from an actual host cursor move. */
class KeyboardSelectionTracker {
    private val pending = ArrayDeque<Selection>()
    var selection = Selection(-1, -1); private set
    fun reset(value: Selection) { pending.clear(); selection = value }
    fun expect(value: Selection) {
        if (!value.valid) { reset(value); return }
        if (pending.size == 32) pending.removeFirst()
        pending.addLast(value); selection = value
    }
    fun observe(value: Selection) {
        // Preview reads can arrive between queued edits and their callbacks.
        if (pending.isEmpty() || value != selection && value !in pending) reset(value)
    }
    fun acknowledge(old: Selection, next: Selection): Boolean {
        // A move away from our latest predicted position is a real host change,
        // even if the destination happens to match an older pending position.
        if (old == selection && next != selection) { reset(next); return false }
        val index = pending.indexOf(next)
        if (index >= 0) { repeat(index + 1) { pending.removeFirst() }; return true }
        // An unchanged caret without a pending write may still mean that the
        // host cancelled/replaced its composing span. Let the caller inspect it.
        reset(next); return false
    }
}
