# iOS

오픈 키보드(Open Keyboard, 임시 이름)의 iOS 앱과 키보드 확장이다. 한글 입력은 기기 안에서만 처리하며 서버, 계정, 결제, 분석, 광고가 없다. 앱과 확장 모두 네트워크를 쓰지 않는다.

The iOS app and keyboard extension of Open Keyboard (working name). Hangul input is processed on the device only: no server, accounts, purchases, analytics or ads, and neither the app nor the extension uses the network.

## 기능 / Features

- 두벌식, 천지인, 모아키 배열과 영문 QWERTY, 숫자·기호 자판 / Dubeolsik, Cheonjiin and Moaki layouts, English QWERTY, numbers and symbols
- 이모지 패널, 키 높이, 진동, 입력 소리 / Emoji panel, key height, haptics, key sounds
- 단축어(마지막 단어가 단축어이면 키 위에 바꿀 문구가 표시됨), 자주 쓰는 문구, 클립보드 기록(메모리에만 보관) / Shortcuts (the expansion appears above the keys when the last word matches), saved phrases, clipboard history (memory only)
- 스페이스를 길게 눌러 끌면 커서 이동, 삭제 키를 길게 누르거나 왼쪽으로 밀어 여러 글자 삭제 / Hold and drag space to move the cursor; hold or slide delete to remove more

전체 접근(Full Access)은 선택 사항이다. 입력 소리, 클립보드 기록, 키보드에서 바꾼 언어 저장에만 필요하다. Full Access is optional; it is needed only for key sounds, clipboard history and saving a language switch made on the keyboard.

## 구성 / Layout

- `KeyboardCore/`: 순수 Swift 패키지. 한글 조합, 모아키 제스처, 터치 판정과 다음 자모 예측, 삭제 제스처, 키 피드백, 단축어·문구·클립보드 / Pure Swift package: Hangul composition, Moaki gestures, touch resolution and next-jamo prediction, delete gestures, key feedback, shortcuts, phrases and clipboard.
- `Keyboard/`: UIKit 키보드 확장 / UIKit keyboard extension.
- `App/`: SwiftUI 설정 앱 / SwiftUI settings app.
- `Shared/`: 앱과 확장이 함께 쓰는 설정 저장, 문자열, 색 / Settings store, strings and colors shared by both targets.
- `Config/Product.xcconfig`: 이름, 번들 접두사, 앱 그룹, 버전 / Name, bundle prefix, App Group, version.

## 요구 사항 / Requirements

Xcode 27.1 (iOS 27 SDK, Swift 6.4 toolchain, Swift 5 language mode)로 빌드를 확인했다. 최소 배포 대상은 iOS 16.0이다. Command Line Tools만으로는 앱을 빌드할 수 없고 전체 Xcode가 필요하다.

Built with Xcode 27.1 (iOS 27 SDK, Swift 6.4 toolchain in Swift 5 language mode). The deployment target is iOS 16.0. A full Xcode install is required; Command Line Tools alone cannot build the app.

## 내 팀과 번들 접두사 설정 / Your team and bundle prefix

1. `Config/Product.xcconfig`의 `PRODUCT_BUNDLE_IDENTIFIER_PREFIX`를 내 접두사로 바꾼다. 확장은 `<접두사>.keyboard`, 앱 그룹은 `group.<접두사>`로 자동으로 정해진다. 이름을 바꾸려면 같은 파일의 `PRODUCT_DISPLAY_NAME`(영문)과 `PRODUCT_DISPLAY_NAME_KO`(한국어)를 바꾼다.
2. 팀 ID는 저장소에 넣지 않는다. 무시되는 `Config/Local.xcconfig`를 만들어 `DEVELOPMENT_TEAM = <팀 ID>`를 넣는다.
3. Apple Developer에서 두 번들 ID와 앱 그룹을 등록하고 두 타깃에 같은 앱 그룹을 연결한다(자동 서명이면 Xcode가 처리한다).

1. Set `PRODUCT_BUNDLE_IDENTIFIER_PREFIX` in `Config/Product.xcconfig`. The extension becomes `<prefix>.keyboard` and the App Group `group.<prefix>`. To rename the product, change `PRODUCT_DISPLAY_NAME` (English) and `PRODUCT_DISPLAY_NAME_KO` (Korean) in the same file.
2. Keep your team ID out of the repository: create the ignored `Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <your team ID>`.
3. Register both bundle IDs and the App Group, and give both targets that App Group (automatic signing does this for you).

## 빌드 / Build

```sh
# 순수 코어 테스트 / core tests
cd ios/KeyboardCore && swift test

# 서명 없이 시뮬레이터용 빌드 / simulator build without signing
xcodebuild -project ios/Keyboard.xcodeproj -scheme Application \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Swift 파일을 추가하거나 지우면 `python3 ios/Scripts/generate_project.py`로 프로젝트를 다시 만든다. 앱 아이콘은 `swift ios/Scripts/generate_icon.swift`가 시스템 글꼴로 그린 임시 아이콘이다.

After adding or removing Swift files, regenerate the project with `python3 ios/Scripts/generate_project.py`. The app icon is a neutral placeholder drawn with the system font by `swift ios/Scripts/generate_icon.swift`.

기기에서 실행한 뒤 설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가에서 키보드를 추가한다. After installing, add the keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.

## 문자열 / Strings

코드의 한국어 문장이 그대로 키이고, 영어는 `Resources/en.lproj/Localizable.strings`에 있다. 기기 언어가 한국어가 아니면 영어로 표시한다. Korean text in code is the key; English lives in `Resources/en.lproj/Localizable.strings`. Any device language other than Korean shows English.

## 라이선스 / License

MIT. 저장소 루트의 `LICENSE`를 따른다. MIT, per the repository root `LICENSE`.
