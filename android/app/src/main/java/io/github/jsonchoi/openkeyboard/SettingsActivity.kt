package io.github.jsonchoi.openkeyboard

import android.app.Activity
import android.app.AlertDialog
import android.content.ComponentName
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import io.github.jsonchoi.openkeyboard.core.Snippets
import io.github.jsonchoi.openkeyboard.core.TextError
import io.github.jsonchoi.openkeyboard.core.TextShortcut
import io.github.jsonchoi.openkeyboard.core.TextShortcuts

/** One screen: set up the keyboard, tune input, and manage shortcuts and snippets. */
class SettingsActivity : Activity() {
    private lateinit var settings: SettingsStore
    private lateinit var root: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var body: LinearLayout
    /** Kept across re-renders so a draft in the try-it field survives a settings change. */
    private lateinit var tryField: EditText
    private val handler = Handler(Looper.getMainLooper())
    // Enabling or picking the keyboard happens in system UI; refresh when the secure setting changes.
    private val setupObserver = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { if (!isDestroyed) render() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        settings = SettingsStore(this)
        @Suppress("DEPRECATION") // Edge-to-edge is the default from Android 15; older releases need the opt-in.
        if (android.os.Build.VERSION.SDK_INT >= 30) window.setDecorFitsSystemWindows(false)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(AppUi.background(this@SettingsActivity)) }
        body = object : LinearLayout(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val width = minOf(MeasureSpec.getSize(widthMeasureSpec), dp(AppUi.CONTENT_WIDTH))
                super.onMeasure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), heightMeasureSpec)
            }
        }.apply { orientation = LinearLayout.VERTICAL; setPadding(dp(AppUi.PAGE), dp(16), dp(AppUi.PAGE), dp(32)) }
        val content = android.widget.FrameLayout(this).apply {
            addView(body, android.widget.FrameLayout.LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        }
        scroll = ScrollView(this).apply { addView(content); isFillViewport = true }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                val ime = insets.getInsets(android.view.WindowInsets.Type.ime())
                view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            insets
        }
        tryField = EditText(this).apply {
            hint = getString(R.string.try_hint); minLines = 3; gravity = Gravity.TOP or Gravity.START
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            AppUi.text(this, 16f); setHintTextColor(AppUi.secondary(this@SettingsActivity))
            background = AppUi.rounded(this@SettingsActivity, AppUi.background(this@SettingsActivity), 12, outlined = true)
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        setContentView(root)
        contentResolver.registerContentObserver(Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD), false, setupObserver)
        contentResolver.registerContentObserver(Settings.Secure.getUriFor(Settings.Secure.ENABLED_INPUT_METHODS), false, setupObserver)
        render()
    }
    override fun onResume() { super.onResume(); render() }
    override fun onDestroy() { contentResolver.unregisterContentObserver(setupObserver); super.onDestroy() }

    private val enabled get() = getSystemService(InputMethodManager::class.java).enabledInputMethodList.any { it.packageName == packageName }
    private val selected get() = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        ?.let(ComponentName::unflattenFromString)?.packageName == packageName

    private fun render() {
        val position = scroll.scrollY
        (tryField.parent as? LinearLayout)?.removeView(tryField)
        body.removeAllViews()
        body.addView(TextView(this).apply {
            text = getString(R.string.app_name); AppUi.text(this, 28f, strong = true); setPadding(dp(4), dp(8), dp(4), dp(4))
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        })
        body.addView(TextView(this).apply { text = getString(R.string.tagline); AppUi.text(this, 15f, muted = true); setPadding(dp(4), 0, dp(4), dp(16)) })
        setup(); input(); shortcuts(); snippets()
        section(R.string.section_try)
        card { body.addView(tryField, LinearLayout.LayoutParams(-1, -2)) }
        body.addView(TextView(this).apply {
            text = getString(R.string.about, versionName()); AppUi.text(this, 13f, muted = true)
            setLineSpacing(dp(3).toFloat(), 1f); setPadding(dp(4), dp(20), dp(4), 0)
        })
        scroll.post { scroll.scrollTo(0, position) }
    }
    private fun setup() {
        section(R.string.section_setup)
        card {
            when {
                !enabled -> {
                    paragraph(getString(R.string.setup_enable_detail, getString(R.string.app_name)))
                    body.addView(KeyboardSettingsPreview(this, selecting = false), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); bottomMargin = dp(12) })
                    button(getString(R.string.setup_enable), primary = true) { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
                }
                !selected -> {
                    paragraph(getString(R.string.setup_select_detail, getString(R.string.app_name)))
                    body.addView(KeyboardSettingsPreview(this, selecting = true), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); bottomMargin = dp(12) })
                    button(getString(R.string.setup_select), primary = true) { getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
                }
                else -> {
                    paragraph(getString(R.string.setup_ready, getString(R.string.app_name)))
                    button(getString(R.string.setup_select)) { getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
                }
            }
        }
    }
    private fun input() {
        section(R.string.section_input)
        card {
            val languages = listOf("ko" to getString(R.string.language_korean), "en" to getString(R.string.language_english))
            row(getString(R.string.typing_language), languages.first { it.first == settings.typingLanguage }.second) {
                choose(getString(R.string.typing_language), languages, settings.typingLanguage) { settings.typingLanguage = it }
            }
            val layouts = listOf("dubeol" to getString(R.string.layout_dubeol), "cheonjiin" to getString(R.string.layout_cheonjiin), "moaki" to getString(R.string.layout_moaki))
            row(getString(R.string.korean_layout), layouts.first { it.first == settings.layout }.second) {
                choose(getString(R.string.korean_layout), layouts, settings.layout) { settings.layout = it }
            }
            if (settings.layout == "moaki") paragraph(getString(R.string.moaki_hint))
            val height = TextView(this).apply { text = getString(R.string.key_height, settings.keyHeight); AppUi.text(this, 16f); setPadding(dp(4), dp(16), dp(4), dp(4)) }
            body.addView(height)
            body.addView(SeekBar(this).apply {
                max = SettingsStore.MAX_KEY_HEIGHT - SettingsStore.MIN_KEY_HEIGHT; progress = settings.keyHeight - SettingsStore.MIN_KEY_HEIGHT
                contentDescription = getString(R.string.key_height_description, SettingsStore.MIN_KEY_HEIGHT, SettingsStore.MAX_KEY_HEIGHT)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                        if (fromUser) { settings.keyHeight = SettingsStore.MIN_KEY_HEIGHT + progress; height.text = getString(R.string.key_height, settings.keyHeight) }
                    }
                    override fun onStartTrackingTouch(bar: SeekBar?) {}
                    override fun onStopTrackingTouch(bar: SeekBar?) {}
                })
            }, LinearLayout.LayoutParams(-1, dp(48)))
            toggle(getString(R.string.haptic), settings.haptic) { settings.haptic = it }
            toggle(getString(R.string.sound), settings.sound) { settings.sound = it }
        }
    }
    private fun shortcuts() {
        section(R.string.section_shortcuts)
        card {
            paragraph(getString(R.string.shortcuts_detail))
            settings.shortcuts.forEach { entry -> row(entry.trigger, entry.expansion) { editShortcut(entry) } }
            button(getString(R.string.add_shortcut), enabled = settings.shortcuts.size < TextShortcuts.MAX_COUNT) { editShortcut(null) }
        }
    }
    private fun snippets() {
        section(R.string.section_snippets)
        card {
            paragraph(getString(R.string.snippets_detail))
            settings.snippets.forEach { value -> row(value.replace('\n', ' '), "") { editSnippet(value) } }
            button(getString(R.string.add_snippet), enabled = settings.snippets.size < Snippets.MAX_COUNT) { editSnippet(null) }
        }
    }
    private fun editShortcut(existing: TextShortcut?) {
        val trigger = field(getString(R.string.shortcut_trigger), existing?.trigger, singleLine = true)
        val expansion = field(getString(R.string.shortcut_expansion), existing?.expansion, singleLine = false)
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), 0); addView(trigger); addView(expansion) }
        val dialog = AlertDialog.Builder(this).setTitle(if (existing == null) R.string.add_shortcut else R.string.edit_shortcut).setView(form)
            .setPositiveButton(R.string.save, null).setNegativeButton(R.string.cancel, null)
            .apply { if (existing != null) setNeutralButton(R.string.delete) { _, _ -> settings.shortcuts = settings.shortcuts.filter { it != existing }; render() } }
            .show()
        // Validate before closing so a rejected entry keeps what the user typed.
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val entry = TextShortcut(trigger.text.toString().trim(), expansion.text.toString())
            val error = TextShortcuts.validate(entry.trigger, entry.expansion, settings.shortcuts, Unicode::graphemes, existing?.trigger)
            if (error != null) { trigger.error = message(error); return@setOnClickListener }
            settings.shortcuts = if (existing == null) settings.shortcuts + entry else settings.shortcuts.map { if (it == existing) entry else it }
            dialog.dismiss(); render()
        }
    }
    private fun editSnippet(existing: String?) {
        val value = field(getString(R.string.snippet_text), existing, singleLine = false)
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), 0); addView(value) }
        val dialog = AlertDialog.Builder(this).setTitle(if (existing == null) R.string.add_snippet else R.string.edit_snippet).setView(form)
            .setPositiveButton(R.string.save, null).setNegativeButton(R.string.cancel, null)
            .apply { if (existing != null) setNeutralButton(R.string.delete) { _, _ -> settings.snippets = settings.snippets.filter { it != existing }; render() } }
            .show()
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val text = value.text.toString().trim()
            val error = Snippets.validate(text, settings.snippets, Unicode::graphemes, existing)
            if (error != null) { value.error = message(error); return@setOnClickListener }
            settings.snippets = if (existing == null) settings.snippets + text else settings.snippets.map { if (it == existing) text else it }
            dialog.dismiss(); render()
        }
    }
    private fun message(error: TextError) = getString(when (error) {
        TextError.TRIGGER_SPACE -> R.string.error_trigger_space
        TextError.TRIGGER_LONG -> R.string.error_trigger_long
        TextError.TEXT_LENGTH -> R.string.error_text_length
        TextError.SAME -> R.string.error_same
        TextError.DUPLICATE -> R.string.error_duplicate
        TextError.FULL -> R.string.error_full
    })
    private fun field(label: String, value: String?, singleLine: Boolean) = EditText(this).apply {
        hint = label; setText(value.orEmpty())
        inputType = InputType.TYPE_CLASS_TEXT or if (singleLine) InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS else InputType.TYPE_TEXT_FLAG_MULTI_LINE
        if (singleLine) isSingleLine = true else maxLines = 5
    }
    private fun choose(title: String, options: List<Pair<String, String>>, current: String, select: (String) -> Unit) {
        AlertDialog.Builder(this).setTitle(title).setSingleChoiceItems(options.map { it.second }.toTypedArray(), options.indexOfFirst { it.first == current }) { dialog, index ->
            select(options[index].first); dialog.dismiss(); render()
        }.setNegativeButton(R.string.cancel, null).show()
    }
    private fun section(title: Int) {
        body.addView(TextView(this).apply { text = getString(title); AppUi.text(this, 13f, strong = true, muted = true); setPadding(dp(4), dp(20), 0, dp(8)) })
    }
    private fun card(build: () -> Unit) {
        val parent = body
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
            background = AppUi.rounded(this@SettingsActivity, AppUi.surface(this@SettingsActivity), AppUi.CARD_RADIUS, outlined = true)
        }
        parent.addView(container, LinearLayout.LayoutParams(-1, -2))
        body = container
        try { build() } finally { body = parent }
    }
    private fun paragraph(text: String) = body.addView(TextView(this).apply {
        this.text = text; AppUi.text(this, 15f, muted = true); setLineSpacing(dp(3).toFloat(), 1f); setPadding(dp(4), dp(6), dp(4), dp(8))
    })
    private fun button(label: String, enabled: Boolean = true, primary: Boolean = false, action: () -> Unit) = body.addView(Button(this).apply {
        text = label; isEnabled = enabled; AppUi.button(this, primary); setOnClickListener { action() }
    }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4); bottomMargin = dp(4) })
    private fun row(title: String, value: String, action: () -> Unit) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(4), dp(12), dp(4), dp(12)); minimumHeight = dp(48)
            background = AppUi.touchBackground(this@SettingsActivity, AppUi.surface(this@SettingsActivity), 10)
            isClickable = true; isFocusable = true; contentDescription = if (value.isEmpty()) title else "$title, $value"
            setOnClickListener { action() }
        }
        row.addView(TextView(this).apply { text = title; AppUi.text(this, 16f); maxLines = 2; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO })
        if (value.isNotEmpty()) row.addView(TextView(this).apply {
            text = value; AppUi.text(this, 14f, muted = true); maxLines = 2; setPadding(0, dp(4), 0, 0); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        })
        body.addView(row)
    }
    private fun toggle(label: String, value: Boolean, change: (Boolean) -> Unit) = body.addView(Switch(this).apply {
        text = label; AppUi.text(this, 16f); isChecked = value; setPadding(dp(4), dp(12), dp(4), dp(12))
        setOnCheckedChangeListener { _, checked -> change(checked) }
    }, LinearLayout.LayoutParams(-1, -2))
    private fun versionName() = packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
    private fun dp(value: Int) = AppUi.dp(this, value)
}
