package io.github.jsonchoi.openkeyboard

import android.content.Context
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.Button
import android.widget.LinearLayout
import io.github.jsonchoi.openkeyboard.core.KeyboardTouchSequence
import io.github.jsonchoi.openkeyboard.core.KeyboardTouchTarget
import io.github.jsonchoi.openkeyboard.core.KeyboardCursorGesture
import io.github.jsonchoi.openkeyboard.core.KoreanTapPrediction

/** One pointer owner per finger, with local hit testing rather than Button click cancellation. */
internal class KeyboardTouchColumn(context: Context) : LinearLayout(context) {
    /** [clampRelease]: a plain click key whose short release drift must not cancel Button's click. */
    private data class Key(val view: Button, val group: Int, val correctable: Boolean = group == 1, val clampRelease: Boolean = false) { val regular get() = group > 0 }
    private data class Finger(val initial: Int, val downTime: Long, var x: Float, var y: Float, var key: Int?, val reach: Map<Int, Float> = emptyMap(), var hold: Runnable? = null, var consumed: Boolean = false, val originX: Float = x, val originY: Float = y, val cursor: KeyboardCursorGesture = KeyboardCursorGesture())
    private val keys = mutableListOf<Key>()
    private var targets = emptyList<KeyboardTouchTarget>()
    // Real view frames; row-edge targets reach further than their views.
    private var frames = emptyList<Rect>()
    private val fingers = mutableMapOf<Int, Finger>()
    private val sequence = KeyboardTouchSequence()
    private val handler = Handler(Looper.getMainLooper())
    private val density get() = resources.displayMetrics.density
    var onSpaceCursor: ((Int) -> Unit)? = null
    var onTouchStart: (() -> Unit)? = null
    /** Touch-down feedback, so haptics and click sound don't wait for the finger to lift. */
    var onPress: ((Button) -> Unit)? = null
    /**
     * The column extends into the strip's bottom by its top padding so a high thumb on the top row still
     * types. Returns true where the strip shows a button or a tappable suggestion: that touch stays the strip's.
     */
    var claimedAbove: ((Float, Float) -> Boolean)? = null
    /** Dubeolsik only: likely next jamo keys reach into their neighbours. */
    var tapPredictionEnabled = false
    /** Keys that leave the prediction alone when pressed (shift before a double consonant). */
    var keepsPrediction: (Button) -> Boolean = { false }
    private val prediction = KoreanTapPrediction()
    fun resetPrediction() = prediction.reset()
    /** Every jamo key's reach for the next tap; empty (plain geometry) at a word start. */
    private fun predictedReach(): Map<Int, Float> {
        if (!tapPredictionEnabled) return emptyMap()
        val reach = HashMap<Int, Float>()
        for (id in keys.indices) if (keys[id].group == 1 && id < targets.size) prediction.reach(keys[id].view.text.toString())?.let { reach[id] = it }
        return reach
    }
    fun owns(view: android.view.View) = keys.any { it.view === view }

    fun registerKey(view: Button, regular: Boolean, space: Boolean = false, correctable: Boolean = regular, clampRelease: Boolean = false) { keys += Key(view, if (space) 2 else if (regular) 1 else 0, correctable, clampRelease) }
    fun resetKeys() { cancelTouches(); keys.clear(); targets = emptyList(); frames = emptyList() }
    fun cancelTouches() {
        val active = fingers.toMap(); fingers.clear(); sequence.cancelAll()
        for ((_, finger) in active) {
            finger.hold?.let(handler::removeCallbacks)
            if (keys.getOrNull(finger.initial)?.regular == false) forward(finger, MotionEvent.ACTION_CANCEL, android.os.SystemClock.uptimeMillis())
        }
        keys.forEach { it.view.isPressed = false }
    }
    override fun onDetachedFromWindow() { cancelTouches(); super.onDetachedFromWindow() }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        fun collect(parent: android.view.ViewGroup) {
            for (index in 0 until parent.childCount) {
                val child = parent.getChildAt(index)
                if (child is Button && keys.none { it.view === child }) keys += Key(child, 0)
                else if (child is android.view.ViewGroup) collect(child)
            }
        }
        collect(this)
        val nextFrames = keys.map { key ->
            val rect = Rect(); key.view.getDrawingRect(rect); offsetDescendantRectToMyCoords(key.view, rect)
            rect
        }
        val rowTops = nextFrames.map { it.top }.distinct().sorted()
        // Each row's outer keys own the inset beside them (for example around ㅁ and ㅣ) and the
        // keyboard window's own padding, which the window routes here; the bottom row owns the
        // strip below it. A press anywhere on the keyboard types the nearest key.
        val host = parent as? android.view.View
        val outerLeft = host?.paddingLeft ?: 0; val outerRight = host?.paddingRight ?: 0; val outerBottom = host?.paddingBottom ?: 0
        val visible = nextFrames.indices.filter { keys[it].view.isShown && !nextFrames[it].isEmpty }
        val leftEdge = visible.groupBy { nextFrames[it].top }.values.map { row -> row.minBy { nextFrames[it].left } }.toSet()
        val rightEdge = visible.groupBy { nextFrames[it].top }.values.map { row -> row.maxBy { nextFrames[it].right } }.toSet()
        val bottomTop = visible.maxOfOrNull { nextFrames[it].top }
        val topTop = visible.minOfOrNull { nextFrames[it].top }
        val next = keys.mapIndexed { id, key ->
            val rect = nextFrames[id]
            val left = if (id in leftEdge) minOf(rect.left, paddingLeft) - outerLeft else rect.left
            val right = if (id in rightEdge) maxOf(rect.right, width - paddingRight) + outerRight else rect.right
            val bottom = if (id in visible && rect.top == bottomTop) maxOf(rect.bottom, height - paddingBottom) + outerBottom else rect.bottom
            // The top row also owns the reach above it (this view's top padding over the strip).
            val top = if (id in visible && rect.top == topTop) minOf(rect.top, 0) else rect.top
            KeyboardTouchTarget(id, left.toFloat(), top.toFloat(), (right - left).toFloat(), (bottom - top).toFloat(), key.group, rowTops.indexOf(rect.top), key.correctable)
        }
        // Gesture navigation claims swipes that start near the screen's side edges as Back and
        // cancels the touch, which dropped edge keys such as ㅔ and ㅣ when a thumb lifted inward.
        // Keep Back on the bottom function row, and give the typing rows to the keyboard.
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            val letterBottom = visible.filter { nextFrames[it].top != bottomTop }.maxOfOrNull { nextFrames[it].bottom }
            val top = visible.minOfOrNull { nextFrames[it].top }
            systemGestureExclusionRects = if (top != null && letterBottom != null && letterBottom > top) listOf(Rect(0, top, width, letterBottom)) else emptyList()
        }
        // Row heights can change while typing (the strip appears or the window resizes). Keep fingers that are
        // already down instead of dropping their keys; only a different key set cancels them.
        if (targets.size != next.size) cancelTouches()
        targets = next; frames = nextFrames
    }
    private fun resolve(x: Float, y: Float, current: Int? = null, group: Int? = null, reach: Map<Int, Float> = emptyMap()) = KeyboardTouchTarget.resolve(x, y, targets, current, group, outerMargin = 8 * density, unit = density, reach = reach)
    private fun follow(x: Float, y: Float, current: Int?, group: Int, reach: Map<Int, Float> = emptyMap()) = KeyboardTouchTarget.follow(x, y, targets, current, group, releaseSlack = RELEASE_SLACK, outerMargin = 8 * density, unit = density, reach = reach)
    private fun highlight() {
        val active = sequence.pressedKeys.toSet()
        keys.forEachIndexed { id, key -> if (key.regular) key.view.isPressed = id in active }
    }
    private fun commit(commits: List<KeyboardTouchSequence.Commit>) {
        for (item in commits) {
            fingers[item.pointer]?.hold?.let(handler::removeCallbacks)
            keys.getOrNull(item.key)?.view?.performClick()
        }
        highlight()
    }
    private fun longPress(pointer: Int, finger: Finger) {
        finger.hold?.let(handler::removeCallbacks); finger.hold = null
        val key = finger.key?.let(keys::getOrNull) ?: return
        if (!key.view.isLongClickable) return
        val task = Runnable {
            if (fingers[pointer] === finger && sequence.contains(pointer) && key.view.performLongClick()) {
                sequence.move(pointer, null); finger.key = null; finger.consumed = true; highlight()
            }
        }
        finger.hold = task; handler.postDelayed(task, ViewConfiguration.getLongPressTimeout().toLong())
    }
    /** Click keys see a short drift as still inside, so Button's touch slop doesn't cancel the click. */
    private fun clamped(key: Key, frame: Rect, x: Float, y: Float): Pair<Float, Float> {
        val localX = x - frame.left; val localY = y - frame.top
        if (!key.clampRelease) return localX to localY
        val dx = maxOf(-localX, 0f, localX - frame.width()); val dy = maxOf(-localY, 0f, localY - frame.height())
        val slack = RELEASE_SLACK * density
        if (dx * dx + dy * dy > slack * slack) return localX to localY
        return localX.coerceIn(0f, (frame.width() - 1).coerceAtLeast(0).toFloat()) to localY.coerceIn(0f, (frame.height() - 1).coerceAtLeast(0).toFloat())
    }
    private fun forward(finger: Finger, action: Int, time: Long) {
        val key = keys.getOrNull(finger.initial) ?: return
        val frame = frames.getOrNull(finger.initial) ?: return
        val (x, y) = clamped(key, frame, finger.x, finger.y)
        val sample = MotionEvent.obtain(finger.downTime, time, action, x, y, 0)
        sample.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
        key.view.dispatchTouchEvent(sample); sample.recycle()
    }
    private fun forwardEvent(finger: Finger, event: MotionEvent, index: Int, action: Int) {
        val key = keys.getOrNull(finger.initial) ?: return
        val view = key.view
        val frame = frames.getOrNull(finger.initial) ?: return
        val target = android.graphics.PointF(frame.left.toFloat(), frame.top.toFloat())
        val sample = if (key.clampRelease) {
            val (x, y) = clamped(key, frame, event.getX(index), event.getY(index))
            MotionEvent.obtain(finger.downTime, event.eventTime, action, x, y, 0).apply { source = event.source }
        } else if (event.pointerCount == 1) MotionEvent.obtain(event).apply {
            offsetLocation(-target.x, -target.y); this.action = action
        } else {
            // Preserve each finger's batched path in one event, without extra MOVE on release.
            val history = if (action == MotionEvent.ACTION_MOVE) event.historySize else 0
            MotionEvent.obtain(finger.downTime, if (history > 0) event.getHistoricalEventTime(0) else event.eventTime, action,
                (if (history > 0) event.getHistoricalX(index, 0) else event.getX(index)) - target.x,
                (if (history > 0) event.getHistoricalY(index, 0) else event.getY(index)) - target.y, 0).apply {
                source = event.source
                for (item in 1 until history) addBatch(event.getHistoricalEventTime(item), event.getHistoricalX(index, item) - target.x, event.getHistoricalY(index, item) - target.y, 1f, 1f, 0)
                if (history > 0) addBatch(event.eventTime, event.getX(index) - target.x, event.getY(index) - target.y, 1f, 1f, 0)
            }
        }
        view.dispatchTouchEvent(sample); sample.recycle()
    }
    private fun move(pointer: Int, x: Float, y: Float, time: Long) {
        val finger = fingers[pointer] ?: return
        finger.x = x; finger.y = y
        if (keys.getOrNull(finger.initial)?.regular == false) { forward(finger, MotionEvent.ACTION_MOVE, time); return }
        if (keys.getOrNull(finger.initial)?.group == 2) {
            if (!finger.cursor.active && !sequence.contains(pointer)) return
            val dx = x - finger.originX; val dy = y - finger.originY
            val wasCursor = finger.cursor.active
            val delta = finger.cursor.update(dx, dy, time - finger.downTime, 24 * density, 12 * density)
            if (!wasCursor && finger.cursor.active) {
                prediction.reset()
                sequence.move(pointer, null); commit(sequence.end(pointer))
            }
            if (finger.cursor.active) {
                if (delta != 0) onSpaceCursor?.invoke(delta)
            } else {
                finger.key = follow(x, y, finger.key, 2); sequence.move(pointer, finger.key)
            }
            return
        }
        if (!sequence.contains(pointer) || finger.consumed) return
        val next = follow(x, y, finger.key, 1, finger.reach)
        if (next != finger.key) { finger.key = next; sequence.move(pointer, next); longPress(pointer, finger) }
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val reachIndex = event.actionIndex
                if (event.getY(reachIndex) < paddingTop && claimedAbove?.invoke(event.getX(reachIndex), event.getY(reachIndex)) == true) {
                    // A first finger here goes on to the strip below this view; a later one is ignored.
                    if (event.actionMasked == MotionEvent.ACTION_DOWN) return false
                    highlight(); return true
                }
                onTouchStart?.invoke()
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    // Keyboard gestures need real positions immediately. Frame resampling
                    // can overshoot a quick stroke, then look like a reverse on touch-up.
                    requestUnbufferedDispatch(event)
                    cancelTouches()
                }
                val index = event.actionIndex; val pointer = event.getPointerId(index)
                val x = event.getX(index); val y = event.getY(index)
                val reach = predictedReach()
                val id = resolve(x, y, reach = reach)
                if (BuildConfig.DEBUG) latency("down", event, id)
                if (id != null && keys[id].view.isEnabled) {
                    onPress?.invoke(keys[id].view)
                    // Presses count before release so a finger still down shapes the next prediction.
                    if (keys[id].group == 1) prediction.record(keys[id].view.text.toString()) else if (!keepsPrediction(keys[id].view)) prediction.reset()
                    val regular = keys[id].regular
                    val finger = Finger(id, event.eventTime, x, y, if (regular) id else null, if (keys[id].group == 1) reach else emptyMap())
                    fingers[pointer] = finger; sequence.begin(pointer, finger.key)
                    if (regular && keys[id].group == 1) longPress(pointer, finger)
                    else if (!regular) { commit(sequence.flush()); forwardEvent(finger, event, index, MotionEvent.ACTION_DOWN) }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                // Keep batched corners for Moaki, and route each pointer to its own initial key.
                for (index in 0 until event.pointerCount) {
                    val pointer = event.getPointerId(index); val finger = fingers[pointer] ?: continue
                    if (keys.getOrNull(finger.initial)?.regular == false) forwardEvent(finger, event, index, MotionEvent.ACTION_MOVE)
                    else {
                        for (history in 0 until event.historySize) move(pointer, event.getHistoricalX(index, history), event.getHistoricalY(index, history), event.getHistoricalEventTime(history))
                        move(pointer, event.getX(index), event.getY(index), event.eventTime)
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val index = event.actionIndex; val pointer = event.getPointerId(index)
                val finger = fingers[pointer]
                // Android 13+ marks a palm or grip contact this way; it must not type (MotionEvent docs).
                if (finger != null && android.os.Build.VERSION.SDK_INT >= 33 && event.flags and MotionEvent.FLAG_CANCELED != 0) {
                    finger.hold?.let(handler::removeCallbacks)
                    sequence.cancel(pointer); fingers.remove(pointer); prediction.reset()
                    if (keys.getOrNull(finger.initial)?.regular == false) forward(finger, MotionEvent.ACTION_CANCEL, event.eventTime)
                } else if (finger != null) {
                    val started = android.os.SystemClock.uptimeMillis()
                    val regular = keys.getOrNull(finger.initial)?.regular == true
                    if (regular) move(pointer, event.getX(index), event.getY(index), event.eventTime)
                    finger.hold?.let(handler::removeCallbacks)
                    commit(sequence.end(pointer))
                    fingers.remove(pointer)
                    if (!regular) forwardEvent(finger, event, index, MotionEvent.ACTION_UP)
                    if (BuildConfig.DEBUG) latency("up", event, finger.key ?: finger.initial, android.os.SystemClock.uptimeMillis() - started)
                }
            }
            MotionEvent.ACTION_CANCEL -> cancelTouches()
            else -> return super.dispatchTouchEvent(event)
        }
        highlight(); return true
    }
    /** Debug-only: how long a touch waited for the main thread, and how long its key work took. */
    private fun latency(phase: String, event: MotionEvent, key: Int?, workMillis: Long = 0) {
        val label = key?.let { keys.getOrNull(it)?.view?.contentDescription ?: keys.getOrNull(it)?.view?.text } ?: "none"
        android.util.Log.d("KeyLatency", "$phase key=$label queued=${android.os.SystemClock.uptimeMillis() - event.eventTime - workMillis}ms work=${workMillis}ms")
    }
    private companion object {
        /** Lift-off drift (dp) that still belongs to the pressed key. */
        const val RELEASE_SLACK = 20f
    }
}
