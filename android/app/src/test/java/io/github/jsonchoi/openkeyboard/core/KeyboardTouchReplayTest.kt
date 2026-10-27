package io.github.jsonchoi.openkeyboard.core

import org.junit.Assert.*
import org.junit.Test

class KeyboardTouchReplayTest {
    private data class Contact(var key: Int?, val group: Int)
    private fun legacy(x: Float, y: Float, keys: List<KeyboardTouchTarget>, current: Int?, group: Int?): Int? {
        if (x < keys.minOf { it.x } - 8 || x > keys.maxOf { it.x + it.width } + 8 || y < keys.minOf { it.y } - 8 || y > keys.maxOf { it.y + it.height } + 8) return null
        var nearest: KeyboardTouchTarget? = null; var distance = Float.POSITIVE_INFINITY; var retained: Int? = null
        for (key in keys) {
            if (key.id == current && (group == null || key.group == group) && x >= key.x - 4 && x <= key.x + key.width + 4 && y >= key.y - 4 && y <= key.y + key.height + 4) retained = key.id
            val dx = maxOf(key.x - x, 0f, x - key.x - key.width); val dy = maxOf(key.y - y, 0f, y - key.y - key.height)
            val value = dx * dx + dy * dy
            if (value < distance) { nearest = key; distance = value }
        }
        if (retained != null) return retained
        return nearest?.takeIf { group == null || it.group == group }?.id
    }
    @Test fun sharedReplayMatchesIntendedKeysAndFrozenBaseline() {
        val fixture = checkNotNull(javaClass.getResource("/keyboard_touch_replay.tsv")) { "Missing test resource" }
        var cases = 0; var improvements = 0
        for (line in fixture.readText().lines().filter { it.isNotBlank() && !it.startsWith("#") }) {
            val cells = line.split('|'); assertEquals(6, cells.size)
            val keys = cells[1].split(';').map { text ->
                val n = text.split(',').map(String::toFloat)
                KeyboardTouchTarget(n[0].toInt(), n[1], n[2], n[3], n[4], n[5].toInt(), n[6].toInt())
            }
            val corrections = if (cells[2] == "_") emptyMap() else cells[2].split(';').associate { text ->
                val n = text.split(',').map(String::toFloat)
                n[0].toInt() to KeyboardTouchCorrection(n[1], n[2])
            }
            fun expected(value: String) = if (value == "_") emptyList() else value.split(',').map(String::toInt)
            fun replay(useLegacy: Boolean, scale: Float = 1f): List<Int> {
                val targets = keys.map { it.copy(x = it.x * scale, y = it.y * scale, width = it.width * scale, height = it.height * scale) }
                val contacts = mutableMapOf<Int, Contact>(); val sequence = KeyboardTouchSequence(); val output = mutableListOf<Int>()
                for (event in cells[3].split(';')) {
                    val e = event.split(','); val pointer = e[1].toInt(); val x = e[2].toFloat() * scale; val y = e[3].toFloat() * scale
                    fun resolve(current: Int?, group: Int?) = if (useLegacy) legacy(x, y, targets, current, group) else KeyboardTouchTarget.resolve(x, y, targets, current, group, outerMargin = 8 * scale, unit = scale, corrections = corrections)
                    when (e[0]) {
                        "D" -> resolve(null, null)?.let { key -> contacts[pointer] = Contact(key, targets.first { it.id == key }.group); sequence.begin(pointer, key) }
                        "C" -> { contacts.remove(pointer); sequence.cancel(pointer) }
                        else -> contacts[pointer]?.let { contact ->
                            if (sequence.contains(pointer)) { contact.key = resolve(contact.key, contact.group); sequence.move(pointer, contact.key) }
                            if (e[0] == "U") { output += sequence.end(pointer).map { it.key }; contacts.remove(pointer) }
                        }
                    }
                }
                return output
            }
            val intended = expected(cells[4]); val previous = expected(cells[5])
            assertEquals(cells[0] + " legacy", previous, replay(true))
            for (scale in listOf(1f, 1.5f, 2f, 3f)) assertEquals(cells[0] + " scale=$scale", intended, replay(false, scale))
            if (previous != intended) improvements++; cases++
        }
        assertEquals(16, cases); assertEquals(5, improvements)
        println("Synthetic touch replay: $cases traces at 4 densities, $improvements targeted baseline mismatches corrected; not real-user accuracy")
    }
    @Test fun candidatesAreLocalStableAndRespectGroups() {
        val keys = listOf(KeyboardTouchTarget(0, 0f, 0f, 40f, 44f), KeyboardTouchTarget(1, 46f, 0f, 40f, 44f), KeyboardTouchTarget(2, 92f, 0f, 40f, 44f, 0))
        assertEquals(listOf(0, 1), KeyboardTouchTarget.candidates(43f, 20f, keys, 1))
        assertEquals(listOf(0, 1), KeyboardTouchTarget.candidates(43f, 20f, keys.reversed(), 1))
        assertEquals(listOf(0), KeyboardTouchTarget.candidates(20f, 20f, keys, 1))
        assertTrue(KeyboardTouchTarget.candidates(Float.NaN, 20f, keys).isEmpty())
        assertTrue(KeyboardTouchTarget.candidates(20f, 20f, keys, limit = 0).isEmpty())
        assertNull(KeyboardTouchTarget.resolve(Float.POSITIVE_INFINITY, 20f, keys))
        assertEquals(0, KeyboardTouchTarget.resolve(20f, 20f, listOf(KeyboardTouchTarget(99, Float.NaN, 0f, 0f, 44f)) + keys))
    }
    @Test fun calibrationIsBoundedAndDoesNotMoveControls() {
        val invalid = KeyboardTouchCorrection(Float.NaN, Float.POSITIVE_INFINITY)
        assertEquals(0f, invalid.verticalOffset); assertEquals(1f, invalid.radiusScale)
        val bounded = KeyboardTouchCorrection(100f, -1f)
        assertEquals(0.25f, bounded.verticalOffset); assertEquals(0.75f, bounded.radiusScale)
        val control = KeyboardTouchTarget(9, 0f, 0f, 40f, 44f, 0)
        assertEquals(9, KeyboardTouchTarget.resolve(20f, -7f, listOf(control), corrections = mapOf(0 to bounded)))
        val overlapping = KeyboardTouchTarget(1, 0f, -48f, 40f, 44f, row = 1)
        assertEquals(9, KeyboardTouchTarget.resolve(20f, 2f, listOf(overlapping, control), corrections = mapOf(1 to bounded)))
        assertNull(KeyboardTouchTarget.resolve(20f, 2f, listOf(overlapping, control), group = 1, corrections = mapOf(1 to bounded)))
    }
}
