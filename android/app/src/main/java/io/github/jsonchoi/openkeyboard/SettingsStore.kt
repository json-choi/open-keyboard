package io.github.jsonchoi.openkeyboard

import android.content.Context
import io.github.jsonchoi.openkeyboard.core.LanguageSupport
import io.github.jsonchoi.openkeyboard.core.TextShortcut
import org.json.JSONArray
import org.json.JSONObject

/** Local preferences shared by the settings screen and the keyboard. Nothing here leaves the device. */
class SettingsStore(context: Context) {
    private val context = context.applicationContext
    private val prefs = context.getSharedPreferences("keyboard_settings_v1", Context.MODE_PRIVATE)
    var typingLanguage: String
        get() = prefs.getString("typingLanguage", null)?.takeIf { it in LanguageSupport.typingLanguages }
            ?: LanguageSupport.typingLanguage((0 until context.resources.configuration.locales.size()).map { context.resources.configuration.locales[it].toLanguageTag() })
        set(value) { if (value in LanguageSupport.typingLanguages) prefs.edit().putString("typingLanguage", value).apply() }
    /** "dubeol", "cheonjiin" or "moaki". */
    var layout: String
        get() = prefs.getString("layout", null)?.takeIf { it in LAYOUTS } ?: "dubeol"
        set(value) { if (value in LAYOUTS) prefs.edit().putString("layout", value).apply() }
    var keyHeight: Int
        get() = prefs.getInt("keyHeight", 52).coerceIn(MIN_KEY_HEIGHT, MAX_KEY_HEIGHT)
        set(value) { prefs.edit().putInt("keyHeight", value.coerceIn(MIN_KEY_HEIGHT, MAX_KEY_HEIGHT)).apply() }
    var sound: Boolean
        get() = prefs.getBoolean("sound", false)
        set(value) { prefs.edit().putBoolean("sound", value).apply() }
    var haptic: Boolean
        get() = prefs.getBoolean("haptic", false) // Off by default; key feedback is opt-in.
        set(value) { prefs.edit().putBoolean("haptic", value).apply() }
    /** Local text replacement entries, matched on device only. */
    var shortcuts: List<TextShortcut>
        get() = runCatching { val a = JSONArray(prefs.getString("shortcuts", "[]")); (0 until a.length()).map { a.getJSONObject(it).let { o -> TextShortcut(o.getString("t"), o.getString("e")) } } }.getOrDefault(emptyList())
        set(value) { prefs.edit().putString("shortcuts", JSONArray(value.map { JSONObject().put("t", it.trigger).put("e", it.expansion) }).toString()).apply() }
    var snippets: List<String>
        get() = runCatching { val a = JSONArray(prefs.getString("snippets", "[]")); (0 until a.length()).map(a::getString) }.getOrDefault(emptyList())
        set(value) { prefs.edit().putString("snippets", JSONArray(value).toString()).apply() }
    companion object {
        val LAYOUTS = listOf("dubeol", "cheonjiin", "moaki")
        const val MIN_KEY_HEIGHT = 44
        const val MAX_KEY_HEIGHT = 64
    }
}
