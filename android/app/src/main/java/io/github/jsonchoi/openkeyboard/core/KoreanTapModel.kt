// Counts derived offline from 2523 CC0 Korean sentences; no sentence text ships with the app.
package io.github.jsonchoi.openkeyboard.core

/** Per automaton state: how often the next key continued a compound, was a consonant, or was a vowel. */
internal object KoreanTapModel {
    val CLASS_COUNTS = intArrayOf(0, 23719, 0, 0, 420, 41172, 4706, 14018, 0, 0, 37580, 0, 3129, 9564, 6699, 0, 8249, 16611)
}
