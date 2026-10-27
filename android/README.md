# Open Keyboard for Android (오픈 키보드)

An offline Hangul keyboard for Android. It has no server, account, purchase, analytics or ads, and the app
does not request the `INTERNET` permission, so nothing you type can leave the device.

"Open Keyboard" is a working name. The display name lives in `app/src/main/res/values*/strings.xml`
(`app_name`), and the application id and Kotlin namespace live in `app/build.gradle.kts` (`appId`).

## Features

- Korean layouts: Dubeolsik (두벌식), Cheonjiin (천지인) and Moaki (모아키, drag from a consonant to add a vowel).
- English QWERTY with Shift and Caps Lock, plus number and symbol pages.
- Dubeolsik tap prediction: likely next jamo keys grow slightly into their neighbours. The prediction is a small
  table of letter-class counts; it holds no text.
- Space-bar cursor drag, held delete that speeds up and then deletes words, and slide-left-to-select on delete.
- Long-press accents (á, é, ...) and currency, a local emoji panel.
- Shortcuts (단축어): type a shortcut as a whole word, then tap the suggestion above the keys.
- Snippets (상용구): saved phrases shown above the keys, inserted with one tap.
- Key height, key vibration and key sound settings. Light and dark follow the system.
- Password, PIN and similar fields are never read: the keyboard types there but shortcuts and cursor reads stay off.
- User interface in English and Korean.

## Requirements

- JDK 17 or newer. Android Studio's bundled JBR works.
- Android SDK with platform 36 (`compileSdk 36`). The app runs on Android 8.0 (API 26) and newer.
- Gradle 8.13 (through the included wrapper), Android Gradle Plugin 8.13.2 and Kotlin 2.2.21.
- No other dependencies. JUnit 4 is used only for unit tests.

Point Gradle at the SDK with `ANDROID_HOME` or a `local.properties` file containing `sdk.dir=/path/to/sdk`.

## Build and install

```sh
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"   # macOS example
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Tests and lint:

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug
./gradlew -p core-tests test     # the same core tests on a plain JVM, no Android SDK needed
```

`core-tests` is a separate Gradle build that compiles `app/src/main/java/.../core` together with the unit tests.

## Enable the keyboard

1. Open the app. The setup card shows the next step.
2. Tap **Turn on keyboard** (키보드 켜기) and turn on Open Keyboard in the system keyboard list.
   Android shows a standard warning that a keyboard can see what you type; this keyboard has no network access.
3. Back in the app, tap **Choose keyboard** (키보드 고르기) and pick Open Keyboard.
4. Type in the **Try it** (써 보기) field to check it.

You can also reach the system screen from Settings > System > Keyboard (the exact path varies by device).

## Release signing

Debug builds use the Android SDK's debug keystore, and the release build type has no signing configuration.
To sign a release with your own key, keep the keystore and passwords out of the repository (the `.gitignore`
already ignores `*.jks`, `*.keystore` and `keystore.properties`) and add a signing config, for example:

```kotlin
// app/build.gradle.kts
val keystore = java.util.Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.isFile }?.inputStream()?.use { load(it) }
}
android {
    signingConfigs {
        create("release") {
            storeFile = keystore.getProperty("storeFile")?.let(::file)
            storePassword = keystore.getProperty("storePassword")
            keyAlias = keystore.getProperty("keyAlias")
            keyPassword = keystore.getProperty("keyPassword")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
}
```

Then run `./gradlew :app:assembleRelease` or `:app:bundleRelease`.

## Layout

- `app/src/main/java/.../core/`: pure Kotlin with no Android imports: Hangul and Cheonjiin composition,
  Moaki gestures, touch targeting and tap prediction, delete pacing, selection tracking, shortcut and snippet rules.
- `KeyboardService.kt`: the input method service and key rendering.
- `KeyboardTouchColumn.kt`: per-finger touch ownership and hit testing for the key rows.
- `SuggestionStrip.kt`, `NativeEmojiPanel.kt`, `EmojiCatalog.kt`: the strip above the keys and the emoji panel.
- `SettingsActivity.kt`, `SettingsStore.kt`, `KeyboardSettingsPreview.kt`: the settings screen and local preferences.

## License

MIT. See the `LICENSE` file at the repository root.
