package io.github.jsonchoi.openkeyboard

import android.content.Context
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView

/** Local Unicode insertion from [EmojiCatalog]. Never reads the draft. */
class NativeEmojiPanel(context: Context, private val settings: SettingsStore,
    private val insert: (String) -> Unit, private val delete: () -> Unit, private val back: () -> Unit
) : LinearLayout(context) {
    private val tabs = LinearLayout(context)
    private val scroll = ScrollView(context)
    private val grid = LinearLayout(context).apply { orientation = VERTICAL }
    private val returnKey = Button(context)
    private var category = 0
    private var columns = 0
    init {
        orientation = VERTICAL
        tabs.orientation = HORIZONTAL
        EmojiCatalog.groups.forEachIndexed { index, group ->
            tabs.addView(Button(context).apply {
                text = group.symbol; setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, minOf(sp(24f), dp(30).toFloat())); contentDescription = context.getString(group.title)
                isAllCaps = false; minWidth = 0; minimumWidth = 0
                includeFontPadding = false; gravity = Gravity.CENTER
                setPadding(0, 0, 0, 0); background = null
                setOnClickListener { select(index) }
            }, LayoutParams(0, dp(44), 1f))
        }
        addView(tabs, LayoutParams(-1, dp(44)))
        scroll.addView(grid, android.widget.FrameLayout.LayoutParams(-1, -2)); addView(scroll, LayoutParams(-1, 0, 1f))
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL; isBaselineAligned = false
            addView(returnKey.apply {
                AppUi.button(this, compact = true); refreshLanguage()
                setPadding(dp(6), 0, dp(6), 0); isSingleLine = true; gravity = Gravity.CENTER
                setAutoSizeTextTypeUniformWithConfiguration(8, 14, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
                contentDescription = context.getString(R.string.back_to_keyboard); setOnClickListener { back() }
            }, LayoutParams(dp(72), dp(44)))
            addView(android.widget.TextView(context).apply {
                text = context.getString(R.string.emoji); gravity = Gravity.CENTER; includeFontPadding = false; setTextColor(AppUi.secondary(context))
            }, LayoutParams(0, -1, 1f))
            addView(AppIconButton(context, "delete").apply {
                background = AppUi.touchBackground(context, AppUi.surface(context), 12)
                contentDescription = context.getString(R.string.key_delete); setOnClickListener { delete() }
            }, LayoutParams(dp(72), dp(44)))
        }, LayoutParams(-1, dp(44)))
        select(0)
    }
    fun refreshLanguage() { returnKey.text = if (settings.typingLanguage == "ko") "가나다" else "ABC" }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // Populate before ScrollView measures its content; doing this during layout leaves a zero-height grid.
        val count = (MeasureSpec.getSize(widthMeasureSpec) / dp(45)).coerceAtLeast(1)
        if (count != columns) { columns = count; render() }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
    private fun select(index: Int) {
        category = index
        for (i in 0 until tabs.childCount) tabs.getChildAt(i).apply {
            isSelected = i == index
            background = if (isSelected) AppUi.rounded(context, AppUi.softAccent(context), 8) else null
        }
        render(); scroll.scrollTo(0, 0)
    }
    private fun render() {
        if (columns == 0) return
        grid.removeAllViews()
        EmojiCatalog.groups[category].emoji.split(' ').chunked(columns).forEach { emoji ->
            grid.addView(LinearLayout(context).apply {
                orientation = HORIZONTAL
                repeat(columns) { index ->
                    addView(Button(context).apply {
                        minWidth = 0; minimumWidth = 0; setPadding(0, 0, 0, 0); background = null
                        setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, minOf(sp(29f), dp(34).toFloat()))
                        includeFontPadding = false; gravity = Gravity.CENTER
                        if (index < emoji.size) {
                            val value = emoji[index]; text = value; contentDescription = value
                            setOnClickListener { insert(value) }
                        } else { isEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }
                    }, LayoutParams(0, dp(44), 1f))
                }
            }, LayoutParams(-1, dp(44)))
        }
    }
    private fun dp(value: Int) = AppUi.dp(context, value)
    private fun sp(value: Float) = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics)
}
