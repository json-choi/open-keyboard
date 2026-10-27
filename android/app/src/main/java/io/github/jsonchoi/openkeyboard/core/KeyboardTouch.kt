package io.github.jsonchoi.openkeyboard.core

/** Explicit row calibration in fractions of key height. Neutral until measured. */
class KeyboardTouchCorrection(verticalOffset: Float = 0f, radiusScale: Float = 1f) {
    val verticalOffset = if (verticalOffset.isFinite()) verticalOffset.coerceIn(-0.25f, 0.25f) else 0f
    val radiusScale = if (radiusScale.isFinite()) radiusScale.coerceIn(0.75f, 1.5f) else 1f
}

/** Local geometry only. Candidates never automatically replace the chosen key. */
data class KeyboardTouchTarget(val id: Int, val x: Float, val y: Float, val width: Float, val height: Float, val group: Int = 1, val row: Int = 0, val correctable: Boolean = group == 1) {
    private val valid get() = x.isFinite() && y.isFinite() && width.isFinite() && height.isFinite() && width > 0 && height > 0
    private fun correctedY(corrections: Map<Int, KeyboardTouchCorrection>) = y + (if (correctable) (corrections[row]?.verticalOffset ?: 0f) * height else 0f)
    private fun distance(px: Float, py: Float, corrections: Map<Int, KeyboardTouchCorrection>): Float {
        val top = correctedY(corrections)
        val dx = maxOf(x - px, 0f, px - x - width); val dy = maxOf(top - py, 0f, py - top - height)
        return dx * dx + dy * dy
    }
    /**
     * Distance to the key's edge in its own widths and heights: positive outside, negative inside
     * (how deep the touch is). Equal-sized neighbours meet exactly where they are drawn. Heights count
     * at [VERTICAL_REACH], since taps scatter less up and down than sideways relative to key size.
     */
    private fun depth(px: Float, py: Float, corrections: Map<Int, KeyboardTouchCorrection>): Float {
        val top = correctedY(corrections); val tall = height * VERTICAL_REACH
        val dx = maxOf(x - px, 0f, px - x - width) / width; val dy = maxOf(top - py, 0f, py - top - height) / tall
        if (dx > 0 || dy > 0) return kotlin.math.sqrt(dx * dx + dy * dy)
        return -minOf(minOf(px - x, x + width - px) / width, minOf(py - top, top + height - py) / tall)
    }
    private fun centerDistance(px: Float, py: Float, corrections: Map<Int, KeyboardTouchCorrection>): Float {
        val dx = (px - x - width / 2) / width; val dy = (py - correctedY(corrections) - height / 2) / height
        return dx * dx + dy * dy
    }
    private fun radius(corrections: Map<Int, KeyboardTouchCorrection>, unit: Float) = maxOf(8 * unit, minOf(width, height) * 0.35f * (if (correctable) corrections[row]?.radiusScale ?: 1f else 1f))
    companion object {
        /**
         * Most of a key's own width or height that a predicted neighbour may take, so the middle half
         * of every key always types that key (Gunawardana et al.'s anchored key-target resizing).
         */
        const val MAX_REACH = 0.25f
        /** Vertical reach relative to sideways reach: σy ≈ 0.20 H against σx ≈ 0.32 W (Adhikary 2023). */
        const val VERTICAL_REACH = 0.5f
        private fun insideEnvelope(x: Float, y: Float, targets: List<KeyboardTouchTarget>, margin: Float): Boolean {
            if (!x.isFinite() || !y.isFinite() || !margin.isFinite() || margin < 0) return false
            var left = Float.POSITIVE_INFINITY; var top = Float.POSITIVE_INFINITY
            var right = Float.NEGATIVE_INFINITY; var bottom = Float.NEGATIVE_INFINITY
            for (key in targets) if (key.valid) {
                left = minOf(left, key.x); top = minOf(top, key.y)
                right = maxOf(right, key.x + key.width); bottom = maxOf(bottom, key.y + key.height)
            }
            return x >= left - margin && x <= right + margin && y >= top - margin && y <= bottom + margin
        }
        /**
         * Size-aware retention and centre tie-breaking; no candidate allocation while moving.
         * [reach] is each predicted key's share of its own width (0…[MAX_REACH]) that it takes from a
         * neighbour with less reach, sideways, and half that share of its height up and down.
         * Keys missing from a non-empty [reach] (controls, digits) keep everything inside their drawn frame.
         */
        fun resolve(x: Float, y: Float, targets: List<KeyboardTouchTarget>, current: Int? = null, group: Int? = null, hysteresis: Float? = null, outerMargin: Float = 8f, unit: Float = 1f, corrections: Map<Int, KeyboardTouchCorrection> = emptyMap(), reach: Map<Int, Float> = emptyMap()): Int? {
            if (!unit.isFinite() || unit <= 0 || !insideEnvelope(x, y, targets, outerMargin)) return null
            if (corrections.isNotEmpty() || reach.isNotEmpty()) targets.firstOrNull { it.valid && (!it.correctable || reach.isNotEmpty() && it.id !in reach) && it.distance(x, y, emptyMap()) == 0f }?.let { fixed ->
                return fixed.id.takeIf { group == null || fixed.group == group }
            }
            // Past the keyboard's outer edge, keys compete as if the touch were on that edge, so reach
            // never carries a key sideways along the margin over its neighbour.
            var px = x; var py = y
            if (reach.isNotEmpty()) {
                var left = Float.POSITIVE_INFINITY; var top = Float.POSITIVE_INFINITY; var right = Float.NEGATIVE_INFINITY; var bottom = Float.NEGATIVE_INFINITY
                for (key in targets) if (key.valid) { left = minOf(left, key.x); top = minOf(top, key.y); right = maxOf(right, key.x + key.width); bottom = maxOf(bottom, key.y + key.height) }
                px = x.coerceIn(left, right); py = y.coerceIn(top, bottom)
            }
            var nearest: KeyboardTouchTarget? = null; var cost = Float.POSITIVE_INFINITY; var center = Float.POSITIVE_INFINITY; var grown = 0f; var retained: Int? = null
            for (key in targets) if (key.valid) {
                val share = (reach[key.id]?.takeIf { it.isFinite() } ?: 0f).coerceIn(0f, MAX_REACH)
                // Two keys trade the strip between them by the difference of their reach.
                val value = key.depth(px, py, corrections) - 2 * share; val middle = key.centerDistance(px, py, corrections)
                if (key.id == current && (group == null || key.group == group)) {
                    val margin = hysteresis ?: minOf(8 * unit, maxOf(4 * unit, minOf(key.width, key.height) * 0.14f))
                    if (margin.isFinite() && margin >= 0 && key.distance(x, y, corrections) <= margin * margin) retained = key.id
                }
                if (value < cost || (value == cost && (middle < center || (middle == center && key.id < (nearest?.id ?: Int.MAX_VALUE))))) {
                    nearest = key; cost = value; center = middle; grown = share
                }
            }
            if (retained != null) return retained
            val key = nearest ?: return null
            val radius = key.radius(corrections, unit) + grown * maxOf(key.width, key.height)
            val chosen = key.id.takeIf { (group == null || key.group == group) && key.distance(x, y, corrections) <= radius * radius }
            // Prediction may change which key a touch types, never whether it types one.
            if (chosen == null && reach.isNotEmpty()) return resolve(x, y, targets, current, group, hysteresis, outerMargin, unit, corrections)
            return chosen
        }
        /**
         * Tracking for a finger that already owns a key. A short drift onto a control, a gap or past
         * the keyboard edge keeps that key instead of silently dropping the tap; only a deliberate
         * slide (beyond [releaseSlack]) leaves it. Sliding onto another letter still switches keys.
         */
        fun follow(x: Float, y: Float, targets: List<KeyboardTouchTarget>, current: Int?, group: Int? = null, releaseSlack: Float = 20f, outerMargin: Float = 8f, unit: Float = 1f, corrections: Map<Int, KeyboardTouchCorrection> = emptyMap(), reach: Map<Int, Float> = emptyMap()): Int? {
            resolve(x, y, targets, current, group, outerMargin = outerMargin, unit = unit, corrections = corrections, reach = reach)?.let { return it }
            if (current == null || !x.isFinite() || !y.isFinite() || !unit.isFinite() || unit <= 0) return null
            val key = targets.firstOrNull { it.id == current && it.valid && (group == null || it.group == group) } ?: return null
            val slack = releaseSlack * unit
            return current.takeIf { slack.isFinite() && slack >= 0 && key.distance(x, y, corrections) <= slack * slack }
        }
        /** Nearby alternatives for boundary diagnostics and future local composition; no text storage. */
        fun candidates(x: Float, y: Float, targets: List<KeyboardTouchTarget>, group: Int? = null, limit: Int = 3, outerMargin: Float = 8f, unit: Float = 1f, corrections: Map<Int, KeyboardTouchCorrection> = emptyMap()): List<Int> {
            if (limit <= 0 || !unit.isFinite() || unit <= 0 || !insideEnvelope(x, y, targets, outerMargin)) return emptyList()
            if (corrections.isNotEmpty()) targets.firstOrNull { it.valid && !it.correctable && it.distance(x, y, emptyMap()) == 0f }?.let { control ->
                return if (group == null || control.group == group) listOf(control.id) else emptyList()
            }
            return targets.filter { key ->
                val radius = key.radius(corrections, unit)
                key.valid && (group == null || key.group == group) && key.distance(x, y, corrections) <= radius * radius
            }.sortedWith { a, b ->
                val first = a.distance(x, y, corrections); val second = b.distance(x, y, corrections)
                if (first != second) first.compareTo(second)
                else {
                    val ac = a.centerDistance(x, y, corrections); val bc = b.centerDistance(x, y, corrections)
                    if (ac != bc) ac.compareTo(bc) else a.id.compareTo(b.id)
                }
            }.take(minOf(limit, targets.size)).map { it.id }
        }
    }
}

class KeyboardTouchSequence {
    data class Commit(val pointer: Int, val key: Int)
    private data class Press(val pointer: Int, var key: Int?)
    private val presses = mutableListOf<Press>()
    val pressedKeys get() = presses.mapNotNull { it.key }
    fun contains(pointer: Int) = presses.any { it.pointer == pointer }
    fun begin(pointer: Int, key: Int?) { cancel(pointer); presses += Press(pointer, key) }
    fun move(pointer: Int, key: Int?) { presses.firstOrNull { it.pointer == pointer }?.key = key }
    fun end(pointer: Int): List<Commit> {
        val index = presses.indexOfFirst { it.pointer == pointer }; if (index < 0) return emptyList()
        val ready = presses.take(index + 1).mapNotNull { press -> press.key?.let { Commit(press.pointer, it) } }
        repeat(index + 1) { presses.removeAt(0) }; return ready
    }
    fun cancel(pointer: Int) { presses.removeAll { it.pointer == pointer } }
    fun flush(): List<Commit> {
        val ready = presses.mapNotNull { press -> press.key?.let { Commit(press.pointer, it) } }
        presses.clear(); return ready
    }
    fun cancelAll() { presses.clear() }
}

class KeyboardCursorGesture {
    var active = false; private set
    private var position = 0f
    fun update(dx: Float, dy: Float, elapsedMilliseconds: Long, activationDistance: Float = 24f, step: Float = 12f): Int {
        if (step <= 0) return 0
        if (!active) {
            if (elapsedMilliseconds < 280 || kotlin.math.abs(dx) < activationDistance || kotlin.math.abs(dx) <= kotlin.math.abs(dy) * 1.2f) return 0
            active = true; position = if (dx < 0) -activationDistance else activationDistance
        }
        val delta = ((dx - position) / step).toInt()
        position += delta * step
        return delta
    }
}
