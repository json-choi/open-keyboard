package io.github.jsonchoi.openkeyboard

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.StateListDrawable
import android.text.TextUtils
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView

/** Neutral gray colors and spacing for the app and the keyboard; light or dark follows the system. */
object AppUi {
    const val PAGE = 20
    const val CONTENT_WIDTH = 560
    const val CARD_RADIUS = 16
    fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
    fun dark(context: Context) = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private fun pick(context: Context, light: Long, dark: Long) = (if (dark(context)) dark else light).toInt()
    fun background(context: Context) = pick(context, 0xFFF4F4F5, 0xFF121314)
    fun surface(context: Context) = pick(context, 0xFFFFFFFF, 0xFF1F2023)
    fun ink(context: Context) = pick(context, 0xFF1B1C1E, 0xFFECEDEF)
    fun secondary(context: Context) = pick(context, 0xFF5E6168, 0xFFA9ADB4)
    fun accent(context: Context) = pick(context, 0xFF3A5BC7, 0xFF8EA6F2)
    fun onAccent(context: Context) = pick(context, 0xFFFFFFFF, 0xFF121314)
    fun softAccent(context: Context) = pick(context, 0xFFE2E7F7, 0xFF2A3045)
    fun border(context: Context) = pick(context, 0xFFD7D8DC, 0xFF3A3C41)
    fun disabled(context: Context) = pick(context, 0xFFE6E7EA, 0xFF2C2E32)
    fun keyboardBackground(context: Context) = pick(context, 0xFFD5D7DC, 0xFF1A1B1E)
    fun key(context: Context) = pick(context, 0xFFFFFFFF, 0xFF3A3C41)
    fun specialKey(context: Context) = pick(context, 0xFFB4B8C0, 0xFF2A2C30)
    fun pressedKey(context: Context) = pick(context, 0xFF9EA2AA, 0xFF626466)
    fun rounded(context: Context, fill: Int, radius: Int = 16, outlined: Boolean = false): GradientDrawable = GradientDrawable().apply {
        setColor(fill); cornerRadius = dp(context, radius).toFloat()
        if (outlined) setStroke(dp(context, 1), border(context))
    }
    fun touchBackground(context: Context, fill: Int, radius: Int = 14): Drawable = RippleDrawable(
        ColorStateList.valueOf(accent(context) and 0x00FFFFFF or 0x24000000), rounded(context, fill, radius), rounded(context, -1, radius))
    // System fonts keep full CJK fallback; no font files ship with the app.
    fun text(view: TextView, size: Float = 16f, strong: Boolean = false, muted: Boolean = false) {
        view.textSize = size
        view.includeFontPadding = false
        if (view !is android.widget.EditText && android.os.Build.VERSION.SDK_INT >= 33) {
            view.lineBreakWordStyle = android.graphics.text.LineBreakConfig.LINE_BREAK_WORD_STYLE_PHRASE
        }
        view.setTextColor(if (muted) secondary(view.context) else ink(view.context))
        view.typeface = if (strong) Typeface.create("sans-serif-medium", Typeface.NORMAL) else Typeface.DEFAULT
    }
    fun button(view: Button, primary: Boolean = false, compact: Boolean = false) {
        val context = view.context
        text(view, if (compact) 14f else 16f, strong = true)
        view.isAllCaps = false; view.minWidth = 0; view.minimumWidth = 0
        view.minHeight = dp(context, if (compact) 40 else 52); view.minimumHeight = view.minHeight
        view.setPadding(dp(context, if (compact) 12 else 16), dp(context, 10), dp(context, if (compact) 12 else 16), dp(context, 10))
        view.stateListAnimator = null; view.elevation = 0f
        val fill = if (primary) accent(context) else surface(context)
        view.background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_enabled), RippleDrawable(
                ColorStateList.valueOf(accent(context) and 0x00FFFFFF or 0x24000000),
                rounded(context, fill, 12, outlined = !primary), rounded(context, -1, 12)))
            addState(intArrayOf(), rounded(context, disabled(context), 12))
        }
        view.backgroundTintList = null
        val normal = if (primary) onAccent(context) else ink(context)
        view.setTextColor(ColorStateList(arrayOf(intArrayOf(android.R.attr.state_enabled), intArrayOf()), intArrayOf(normal, secondary(context))))
        view.maxLines = 2; view.ellipsize = TextUtils.TruncateAt.END
    }
}

/** Icon-only controls have a view-centered drawable, independent of text/font padding. */
@android.annotation.SuppressLint("AppCompatCustomView")
class AppIconButton(context: Context, kind: String, tint: Int = AppUi.ink(context)) : ImageButton(context) {
    init {
        setImageDrawable(KeyIcon(context, kind, tint))
        scaleType = android.widget.ImageView.ScaleType.CENTER
        setPadding(0, 0, 0, 0)
        minimumWidth = 0; minimumHeight = 0
        backgroundTintList = null; stateListAnimator = null; elevation = 0f
    }
}

/** Key symbols, drawn locally without fonts or image assets. */
class KeyIcon(private val context: Context, private val kind: String, tint: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = tint; style = Paint.Style.STROKE; strokeWidth = 1.8f; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    override fun getIntrinsicWidth() = AppUi.dp(context, 24)
    override fun getIntrinsicHeight() = AppUi.dp(context, 24)
    override fun draw(canvas: Canvas) {
        canvas.save(); canvas.translate(bounds.left.toFloat(), bounds.top.toFloat()); canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
        val path = Path()
        when (kind) {
            "shift" -> { path.moveTo(3f, 11f); path.lineTo(12f, 3f); path.lineTo(21f, 11f); path.lineTo(16f, 11f); path.lineTo(16f, 21f); path.lineTo(8f, 21f); path.lineTo(8f, 11f); path.close() }
            "space" -> { path.moveTo(2f, 10f); path.lineTo(2f, 15f); path.lineTo(22f, 15f); path.lineTo(22f, 10f) }
            "return" -> { path.moveTo(20f, 5f); path.lineTo(20f, 14f); path.lineTo(4f, 14f); path.moveTo(9f, 9f); path.lineTo(4f, 14f); path.lineTo(9f, 19f) }
            "delete" -> {
                path.moveTo(2f, 12f); path.lineTo(8f, 5f); path.lineTo(21f, 5f); path.lineTo(21f, 19f); path.lineTo(8f, 19f); path.close()
                path.moveTo(11f, 9f); path.lineTo(17f, 15f); path.moveTo(17f, 9f); path.lineTo(11f, 15f)
            }
        }
        canvas.drawPath(path, paint)
        canvas.restore()
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter; invalidateSelf() }
    @Deprecated("Deprecated in Android") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
