package io.github.jsonchoi.openkeyboard.core

data class Selection(val start: Int, val end: Int) {
    val low get() = minOf(start, end)
    val high get() = maxOf(start, end)
    val collapsed get() = start == end
    val valid get() = start >= 0 && end >= 0
}
/** One live read around the caret; [selected] is null when the selection is collapsed. */
data class EditorReading(val selection: Selection, val before: String, val selected: String?, val after: String)
