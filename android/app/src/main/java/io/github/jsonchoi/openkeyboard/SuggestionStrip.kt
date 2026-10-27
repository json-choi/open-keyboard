package io.github.jsonchoi.openkeyboard

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.widget.Button
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import io.github.jsonchoi.openkeyboard.core.TextShortcut

/** The row above the keys: a matching shortcut first, then the user's saved snippets. */
class SuggestionStrip(context: Context, private val insertSnippet: (String) -> Unit) : LinearLayout(context) {
    private val chips = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
    private var snippets: List<String> = emptyList()
    private var suggestion: Pair<TextShortcut, () -> Unit>? = null
    init {
        gravity = Gravity.CENTER_VERTICAL
        addView(HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            addView(chips, LayoutParams(-2, -1))
        }, LayoutParams(-1, -1))
    }
    fun setSnippets(values: List<String>) { snippets = values; render() }
    fun suggest(shortcut: TextShortcut?, accept: () -> Unit = {}) {
        if (shortcut == suggestion?.first) return
        suggestion = shortcut?.let { it to accept }; render()
    }
    private fun render() {
        chips.removeAllViews()
        suggestion?.let { (shortcut, accept) ->
            chip(context.getString(R.string.shortcut_suggestion, shortcut.trigger, shortcut.expansion), primary = true) { suggestion = null; render(); accept() }
        }
        snippets.forEach { value -> chip(value.replace('\n', ' '), primary = false) { insertSnippet(value) } }
    }
    private fun chip(label: String, primary: Boolean, action: () -> Unit) {
        chips.addView(Button(context).apply {
            AppUi.button(this, primary = primary, compact = true)
            text = label; isSingleLine = true; ellipsize = TextUtils.TruncateAt.END; maxWidth = AppUi.dp(context, 220)
            minHeight = 0; minimumHeight = 0; setPadding(AppUi.dp(context, 12), 0, AppUi.dp(context, 12), 0)
            setOnClickListener { action() }
        }, LayoutParams(-2, AppUi.dp(context, 34)).apply { marginStart = AppUi.dp(context, 4); marginEnd = AppUi.dp(context, 4) })
    }
}
