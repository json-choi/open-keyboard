package io.github.jsonchoi.openkeyboard.core

/** Screen coordinates relative to touch-down. No host text is changed before release. */
class MoakiGesture(threshold: Double = 12.0) {
    private val threshold = threshold.coerceAtLeast(1.0)
    private var x = 0.0
    private var y = 0.0
    private var path = ""
    private var invalidTurn = false
    private var unrecognizedDistance = 0.0
    fun move(x: Double, y: Double) {
        val dx = x - this.x; val dy = y - this.y
        if (dx * dx + dy * dy < threshold * threshold) return
        val direction = when {
            kotlin.math.abs(dy) < kotlin.math.abs(dx) * 0.41421356237 -> if (dx > 0) 'R' else 'L'
            kotlin.math.abs(dx) < kotlin.math.abs(dy) * 0.41421356237 -> if (dy > 0) 'D' else 'U'
            else -> if (dy > 0) 'E' else 'I'
        }
        this.x = x; this.y = y
        if (path.lastOrNull() != direction) {
            val candidate = path + direction
            if (vowels.keys.any { it.startsWith(candidate) }) {
                path = candidate; invalidTurn = false; unrecognizedDistance = 0.0
            } else {
                unrecognizedDistance += kotlin.math.hypot(dx, dy)
                if (unrecognizedDistance >= threshold * 1.5) invalidTurn = true
            }
        } else unrecognizedDistance = 0.0
    }
    val hasStroke get() = path.isNotEmpty()
    val vowel get() = if (invalidTurn) null else vowels[path]
    fun input(base: String): String? {
        if (!hasStroke) return base.ifEmpty { "ㅣ" }
        return vowel?.let { base + it }
    }
    companion object {
        fun activationDistance(keyWidth: Double, keyHeight: Double): Double {
            if (!keyWidth.isFinite() || !keyHeight.isFinite() || keyWidth <= 0 || keyHeight <= 0) return 12.0
            return (minOf(keyWidth, keyHeight) * 0.24).coerceIn(8.0, 16.0)
        }
        private val vowels = mapOf(
            "R" to 'ㅏ', "RL" to 'ㅐ', "RLR" to 'ㅑ', "RLRL" to 'ㅒ',
            "L" to 'ㅓ', "LR" to 'ㅔ', "LRL" to 'ㅕ', "LRLR" to 'ㅖ',
            "U" to 'ㅗ', "UR" to 'ㅘ', "URL" to 'ㅙ', "UD" to 'ㅚ', "UDU" to 'ㅛ',
            "D" to 'ㅜ', "DL" to 'ㅝ', "DLR" to 'ㅞ', "DU" to 'ㅟ', "DUD" to 'ㅠ',
            "E" to 'ㅡ', "EI" to 'ㅢ', "EU" to 'ㅢ', "I" to 'ㅣ'
        )
    }
}

