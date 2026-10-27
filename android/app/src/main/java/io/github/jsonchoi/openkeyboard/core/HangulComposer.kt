package io.github.jsonchoi.openkeyboard.core

/** Reversible keystroke composition. Buffer exists only while the host composing span exists. */
class HangulComposer {
    private val strokes = mutableListOf<Char>()
    val isEmpty get() = strokes.isEmpty()
    val text get() = compose(strokes)
    fun input(jamo: Char): String { strokes += jamo; return text }
    fun replaceLast(jamo: Char): String { if (strokes.isNotEmpty()) strokes[strokes.lastIndex] = jamo; return text }
    fun backspace(): String { if (strokes.isNotEmpty()) strokes.removeAt(strokes.lastIndex); return text }
    fun clear() { strokes.clear() }

    companion object {
        private val initials = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
        private val vowels = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
        private val finals = "\u0000ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"
        private val vowelPairs = mapOf("ㅗㅏ" to 'ㅘ', "ㅗㅐ" to 'ㅙ', "ㅗㅣ" to 'ㅚ', "ㅜㅓ" to 'ㅝ', "ㅜㅔ" to 'ㅞ', "ㅜㅣ" to 'ㅟ', "ㅡㅣ" to 'ㅢ', "ㅘㅣ" to 'ㅙ', "ㅝㅣ" to 'ㅞ')
        private val finalPairs = mapOf("ㄱㅅ" to 'ㄳ', "ㄴㅈ" to 'ㄵ', "ㄴㅎ" to 'ㄶ', "ㄹㄱ" to 'ㄺ', "ㄹㅁ" to 'ㄻ', "ㄹㅂ" to 'ㄼ', "ㄹㅅ" to 'ㄽ', "ㄹㅌ" to 'ㄾ', "ㄹㅍ" to 'ㄿ', "ㄹㅎ" to 'ㅀ', "ㅂㅅ" to 'ㅄ')
        private val finalSplits = finalPairs.entries.associate { it.value to it.key }
        fun compose(strokes: List<Char>): String {
            val out = StringBuilder()
            var initial: Char? = null
            var vowel: Char? = null
            var final: Char? = null
            fun emit() {
                if (initial != null && vowel != null) {
                    val l = initials.indexOf(initial!!)
                    val v = vowels.indexOf(vowel!!)
                    val t = final?.let { finals.indexOf(it) } ?: 0
                    out.append((0xAC00 + (l * 21 + v) * 28 + t).toChar())
                } else { initial?.let(out::append); vowel?.let(out::append) }
                initial = null; vowel = null; final = null
            }
            for (j in strokes) {
                if (vowels.contains(j)) {
                    when {
                        vowel == null -> vowel = j
                        final != null -> {
                            val split = finalSplits[final]
                            val nextInitial = split?.last() ?: final!!
                            final = split?.first()
                            emit(); initial = nextInitial; vowel = j
                        }
                        else -> {
                            val combined = vowelPairs["$vowel$j"]
                            if (combined != null) vowel = combined else { emit(); vowel = j }
                        }
                    }
                } else if (initials.contains(j)) {
                    when {
                        initial == null && vowel == null -> initial = j
                        initial != null && vowel != null && final == null && finals.contains(j) -> final = j
                        final != null -> {
                            val combined = finalPairs["$final$j"]
                            if (combined != null) final = combined else { emit(); initial = j }
                        }
                        else -> { emit(); initial = j }
                    }
                } else { emit(); out.append(j) }
            }
            emit()
            return out.toString()
        }
    }
}

/** Three vowel strokes and cycling consonant groups, retaining physical strokes for deletion. */
class CheonjiinComposer {
    private val raw = mutableListOf<Char>()
    private var lastGroup = ""
    private var lastTime = 0L
    private var cycle = 0
    val isEmpty get() = raw.isEmpty()
    val text get() = HangulComposer.compose(normalize(raw))
    fun vowel(atom: Char): String { raw += atom; lastGroup = ""; return text }
    fun consonant(group: String, nowMillis: Long): String {
        if (lastGroup == group && nowMillis - lastTime in 0..600 && raw.isNotEmpty()) {
            cycle = (cycle + 1) % group.length; raw[raw.lastIndex] = group[cycle]
        } else { cycle = 0; raw += group[0] }
        lastGroup = group; lastTime = nowMillis
        return text
    }
    fun backspace(): String { if (raw.isNotEmpty()) raw.removeAt(raw.lastIndex); lastGroup = ""; return text }
    fun clear() { raw.clear(); lastGroup = ""; cycle = 0; lastTime = 0 }
    companion object {
        private val patterns = mapOf(
            "ㆍㅡㅣㆍㅣ" to 'ㅙ', "ㅡㆍㆍㅣㅣ" to 'ㅞ',
            "ㅣㆍㆍㅣ" to 'ㅒ', "ㆍㆍㅣㅣ" to 'ㅖ', "ㅡㆍㆍㅣ" to 'ㅝ', "ㆍㅡㅣㆍ" to 'ㅘ',
            "ㅣㆍㆍ" to 'ㅑ', "ㆍㆍㅣ" to 'ㅕ', "ㆍㆍㅡ" to 'ㅛ', "ㅡㆍㆍ" to 'ㅠ',
            "ㅣㆍㅣ" to 'ㅐ', "ㆍㅣㅣ" to 'ㅔ', "ㆍㅡㅣ" to 'ㅚ', "ㅡㆍㅣ" to 'ㅟ',
            "ㅣㆍ" to 'ㅏ', "ㆍㅣ" to 'ㅓ', "ㆍㅡ" to 'ㅗ', "ㅡㆍ" to 'ㅜ', "ㅡㅣ" to 'ㅢ',
            "ㅣ" to 'ㅣ', "ㅡ" to 'ㅡ', "ㆍ" to 'ㆍ'
        )
        fun normalize(raw: List<Char>): List<Char> {
            val result = mutableListOf<Char>()
            var i = 0
            while (i < raw.size) {
                if (raw[i] !in "ㅣㆍㅡ") { result += raw[i++]; continue }
                val remaining = raw.drop(i).takeWhile { it in "ㅣㆍㅡ" }.joinToString("")
                val match = patterns.keys.filter { remaining.startsWith(it) }.maxByOrNull { it.length }!!
                result += patterns.getValue(match); i += match.length
            }
            return result
        }
    }
}
