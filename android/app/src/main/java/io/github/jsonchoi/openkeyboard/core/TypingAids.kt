package io.github.jsonchoi.openkeyboard.core

/**
 * Next-key likelihood for dubeolsik taps, after KeyboardKit's dynamic tap areas and Gunawardana et al.'s
 * anchored key-target resizing. The Hangul automaton (onset, open or closed vowel, open or closed final)
 * decides which keys can come next: a compound continuation (ㅗ→ㅏㅐㅣ, ㄹ→ㄱㅁㅂㅅㅌㅍㅎ), another
 * consonant or another vowel. [KoreanTapModel] says how often each happened; keys of one class share it.
 */
class KoreanTapPrediction {
    private var state = START
    private var last = ' '
    /** Records a pressed key. Anything but a dubeolsik jamo key (space, symbol, delete) starts over. */
    fun record(value: String) {
        val key = value.singleOrNull()?.takeIf { it in KEYS } ?: return reset()
        state = advance(state, last, key); last = key
    }
    fun reset() { state = START; last = ' ' }
    /** Probability that the next tap is [value], or null at a word start, where any key is plausible. */
    fun probability(value: String): Float? {
        val key = value.singleOrNull()?.takeIf { it in KEYS } ?: return null
        return perKey()?.get(kind(state, last, key))
    }
    /**
     * How far [value] reaches into its neighbours (see [KeyboardTouchTarget.resolve]): the likeliest keys
     * reach [KeyboardTouchTarget.MAX_REACH], and each halving of probability gives up [STEEPNESS]·ln 2.
     */
    fun reach(value: String): Float? {
        val chance = probability(value) ?: return null
        val best = perKey()?.max() ?: return null
        return maxOf(0f, KeyboardTouchTarget.MAX_REACH + STEEPNESS * kotlin.math.ln(chance / best))
    }
    /** Each class's probability per key, or null without context. */
    private fun perKey(): FloatArray? {
        if (state == START) return null
        val pairs = if (state == OPEN_VOWEL || state == OPEN_FINAL) PAIRS[last]?.length ?: 0 else 0
        val sizes = intArrayOf(pairs, CONSONANTS - (if (state == OPEN_FINAL) pairs else 0), VOWELS - (if (state == OPEN_VOWEL) pairs else 0))
        // Add-one smoothing over the classes that exist here, so no key is ever impossible.
        val counts = FloatArray(3) { if (sizes[it] > 0) KoreanTapModel.CLASS_COUNTS[state * 3 + it] + 1f else 0f }
        val total = counts.sum()
        return FloatArray(3) { if (sizes[it] > 0) counts[it] / total / sizes[it] else 0f }
    }
    companion object {
        /** The 33 dubeolsik key values, shifted keys included. */
        const val KEYS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅛㅜㅠㅡㅣ"
        /**
         * Reach given up per unit of log-probability: the boundary shift between two Gaussian key models,
         * w·σx² with σx ≈ 0.32 key widths and language weight w ≈ 0.6 (Adhikary 2023; Gunawardana 2010).
         */
        const val STEEPNESS = 0.06f
        private const val CONSONANTS = 19
        private const val VOWELS = 14
        private const val START = 0; private const val ONSET = 1; private const val OPEN_VOWEL = 2
        private const val VOWEL = 3; private const val OPEN_FINAL = 4; private const val FINAL = 5
        private const val PAIR = 0; private const val CONSONANT = 1; private const val VOWEL_CLASS = 2
        /** Vowels that combine with a next vowel, and finals that take a second consonant. */
        private val PAIRS = mapOf('ㅗ' to "ㅏㅐㅣ", 'ㅜ' to "ㅓㅔㅣ", 'ㅡ' to "ㅣ", 'ㄱ' to "ㅅ", 'ㄴ' to "ㅈㅎ", 'ㄹ' to "ㄱㅁㅂㅅㅌㅍㅎ", 'ㅂ' to "ㅅ")
        private const val NEVER_FINAL = "ㄸㅃㅉ"
        private fun vowel(key: Char) = key >= 'ㅏ'
        private fun advance(state: Int, last: Char, key: Char): Int = when {
            vowel(key) -> if (state == OPEN_VOWEL && key in PAIRS[last].orEmpty()) VOWEL else if (key in PAIRS) OPEN_VOWEL else VOWEL
            (state == OPEN_VOWEL || state == VOWEL) && key !in NEVER_FINAL -> if (key in PAIRS) OPEN_FINAL else FINAL
            state == OPEN_FINAL && key in PAIRS[last].orEmpty() -> FINAL
            else -> ONSET
        }
        private fun kind(state: Int, last: Char, key: Char) = when {
            (state == OPEN_VOWEL || state == OPEN_FINAL) && key in PAIRS[last].orEmpty() -> PAIR
            vowel(key) -> VOWEL_CLASS
            else -> CONSONANT
        }
    }
}

/**
 * Held-delete pacing: one character per repeat, two after 20 repeats (HeliBoard's DELETE_ACCELERATE_AT),
 * then a word per repeat once the key has been held for 3 seconds (KeyboardKit's backspace range).
 */
object DeleteRepeat {
    sealed interface Step { data class Characters(val count: Int) : Step; data object Word : Step }
    const val ACCELERATE_AFTER = 20
    const val WORD_AFTER_MILLIS = 3000L
    fun step(repeats: Int, heldMillis: Long): Step = when {
        heldMillis > WORD_AFTER_MILLIS -> Step.Word
        repeats > ACCELERATE_AFTER -> Step.Characters(2)
        else -> Step.Characters(1)
    }
    /** Trailing whitespace plus the last word of [before]; punctuation ends a word once letters were found. */
    fun lastWord(before: String): String {
        val units = before.codePoints().toArray()
        var end = units.size; var letters = false
        while (end > 0 && Character.isWhitespace(units[end - 1])) end--
        while (end > 0) {
            val point = units[end - 1]
            val type = Character.getType(point)
            val delimiter = Character.isWhitespace(point) || type in PUNCTUATION_OR_SYMBOL
            if (delimiter && letters) break
            letters = letters || !delimiter
            end--
        }
        return String(units, end, units.size - end)
    }
    private val PUNCTUATION_OR_SYMBOL = setOf(
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION, Character.END_PUNCTUATION,
        Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION, Character.OTHER_PUNCTUATION,
        Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL, Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL,
    ).map { it.toInt() }.toSet()
    /** HeliBoard's delete slider step: one character per 10dp slid left. */
    const val SLIDE_STEP_DP = 10f
}
