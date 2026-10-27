# Open Keyboard (오픈 키보드)

An offline Hangul keyboard for iOS and Android. It needs no account and has no ads,
analytics or network access: everything you type stays on the device.

오프라인 한글 키보드입니다. 계정, 광고, 분석, 네트워크 접근이 없어서 입력한 내용은 기기 밖으로 나가지 않습니다.

## Features

- Layouts: Dubeolsik (두벌식), Cheonjiin (천지인) and Moaki (모아키) gestures, plus English QWERTY
- Touch targeting that corrects near-miss taps from the next likely key
- Emoji panel, symbols, space-drag cursor and held or slide delete
- Shortcuts (trigger → text) and saved phrases above the keys
- Key height, haptics and key sound settings; light and dark follow the system
- Password, PIN and similar fields are never read

## Layout

| Path | Contents |
|---|---|
| [`ios/`](ios/README.md) | iOS app and keyboard extension (Swift, iOS 16+), with the `KeyboardCore` Swift package and its tests |
| [`android/`](android/README.md) | Android app and input method service (Kotlin, API 26+), with JVM unit tests |

Each folder's README covers requirements, building, signing with your own team or key, and turning
the keyboard on.

## Quick start

```sh
# iOS core tests and a simulator build (set your team in ios/Config/Local.xcconfig to run on a device)
cd ios/KeyboardCore && swift test
cd .. && xcodebuild -project Keyboard.xcodeproj -scheme Application \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Android debug APK and unit tests (JDK 17+)
cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest
```

## License

[MIT](LICENSE)
