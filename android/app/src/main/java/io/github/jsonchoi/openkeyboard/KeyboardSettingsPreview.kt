package io.github.jsonchoi.openkeyboard

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.View

/** Noninteractive sketch of the system screen the next setup step opens: enable, or pick, this keyboard. */
class KeyboardSettingsPreview(context: Context, private val selecting: Boolean) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val dark = AppUi.dark(context)
    private val ink = if (dark) Color.WHITE else 0xFF1F1F1F.toInt()
    private val muted = if (dark) 0xFFBFC2C6.toInt() else 0xFF64676B.toInt()
    private val surface = if (dark) 0xFF25282C.toInt() else 0xFFF0F2F5.toInt()
    private val accent = AppUi.accent(context)
    private val name = context.getString(R.string.app_name)
    // Stands in for whichever keyboard is already installed.
    private val other = context.getString(R.string.preview_other_keyboard)

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = context.getString(R.string.preview_description, context.getString(if (selecting) R.string.setup_select else R.string.setup_enable))
        isClickable = false; isFocusable = false
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(width, (width * 250f / 344f).toInt())
    }
    private fun fill(color: Int) { paint.color = color; paint.style = Paint.Style.FILL }
    private fun label(canvas: Canvas, value: String, x: Float, y: Float, size: Float = 17f, strong: Boolean = false, color: Int = ink, maxWidth: Float = 220f) {
        fill(color); paint.typeface = Typeface.create("sans-serif", if (strong) Typeface.BOLD else Typeface.NORMAL)
        paint.textSize = size
        while (paint.measureText(value) > maxWidth && paint.textSize > 11f) paint.textSize -= 0.5f
        canvas.drawText(value, x, y, paint)
    }
    private fun focus(canvas: Canvas, top: Float, bottom: Float) {
        paint.color = accent; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2.5f
        canvas.drawRoundRect(19f, top, 325f, bottom, 22f, 22f, paint)
        fill(accent); canvas.drawCircle(294f, bottom - 7f, 14f, paint)
        fill(AppUi.onAccent(context))
        val hand = Path().apply {
            moveTo(290f, bottom - 4f); lineTo(287f, bottom - 9f); quadTo(286f, bottom - 12f, 288f, bottom - 11f)
            lineTo(291f, bottom - 8f); lineTo(291f, bottom - 16f); quadTo(291f, bottom - 19f, 294f, bottom - 17f)
            lineTo(294f, bottom - 11f); quadTo(300f, bottom - 14f, 301f, bottom - 8f)
            lineTo(300f, bottom - 2f); quadTo(294f, bottom + 3f, 290f, bottom - 4f); close()
        }
        canvas.drawPath(hand, paint)
    }
    private fun radio(canvas: Canvas, y: Float, checked: Boolean) {
        paint.color = if (checked) accent else muted; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2f
        canvas.drawCircle(46f, y, 9f, paint)
        if (checked) { fill(accent); canvas.drawCircle(46f, y, 4.5f, paint) }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas); canvas.save(); canvas.scale(width / 344f, width / 344f)
        fill(if (dark) 0xFF15171A.toInt() else 0xFFFDFDFD.toInt()); canvas.drawRoundRect(0f, 0f, 344f, 250f, 24f, 24f, paint)
        if (selecting) {
            label(canvas, context.getString(R.string.preview_change_keyboard), 24f, 42f, 20f, true, maxWidth = 296f)
            fill(surface); canvas.drawRoundRect(16f, 67f, 328f, 219f, 24f, 24f, paint)
            radio(canvas, 105f, true); label(canvas, other, 72f, 111f, color = muted)
            radio(canvas, 181f, false); label(canvas, name, 72f, 187f)
            focus(canvas, 147f, 214f)
        } else {
            paint.color = ink; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2f; paint.strokeCap = Paint.Cap.ROUND
            canvas.drawLine(39f, 25f, 29f, 35f, paint); canvas.drawLine(29f, 35f, 39f, 45f, paint); canvas.drawLine(29f, 35f, 48f, 35f, paint)
            label(canvas, context.getString(R.string.preview_onscreen_keyboard), 65f, 42f, 20f, true, maxWidth = 250f)
            fill(surface); canvas.drawRoundRect(16f, 67f, 328f, 219f, 24f, 24f, paint)
            label(canvas, other, 32f, 111f, color = muted, maxWidth = 206f)
            label(canvas, name, 32f, 187f, maxWidth = 206f)
            fill(if (dark) 0xFF5F6368.toInt() else 0xFFCBD0D7.toInt()); canvas.drawRoundRect(258f, 91f, 310f, 119f, 14f, 14f, paint)
            fill(Color.WHITE); canvas.drawCircle(296f, 105f, 10f, paint)
            fill(if (dark) 0xFF5F6368.toInt() else 0xFFCBD0D7.toInt()); canvas.drawRoundRect(258f, 167f, 310f, 195f, 14f, 14f, paint)
            fill(Color.WHITE); canvas.drawCircle(272f, 181f, 10f, paint)
            focus(canvas, 147f, 214f)
        }
        paint.color = AppUi.border(context); paint.style = Paint.Style.STROKE; paint.strokeWidth = 1f
        canvas.drawRoundRect(0.5f, 0.5f, 343.5f, 249.5f, 24f, 24f, paint)
        canvas.restore()
    }
}
