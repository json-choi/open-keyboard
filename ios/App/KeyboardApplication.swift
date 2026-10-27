import SwiftUI
import KeyboardCore

@main struct KeyboardApplication: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }.environmentObject(model)
                // The keyboard may have saved a language switch or recorded Full Access meanwhile.
                .onChange(of: phase) { value in if value == .active { model.reload() } }
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    private let store = SharedSettingsStore()
    @Published var settings: KeyboardSettings { didSet { if settings != oldValue { save() } } }
    @Published private(set) var fullAccessObserved = false
    @Published private(set) var saveFailed = false
    init() { settings = store.read(); fullAccessObserved = KeyboardActivationStore().previouslyActivatedWithFullAccess }
    func reload() {
        let latest = store.read()
        if latest != settings { settings = latest }
        fullAccessObserved = KeyboardActivationStore().previouslyActivatedWithFullAccess
    }
    private func save() {
        do { try store.write(settings); saveFailed = false } catch { saveFailed = true }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var practice = ""
    var body: some View {
        List {
            Section {
                ForEach(Array(setupSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: String(index + 1)).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(step)
                    }
                }
                Button(L("설정 열기")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    .accessibilityIdentifier("open-settings")
            } header: { Text(L("키보드 추가")) } footer: {
                Text(L("전체 접근은 선택 사항이에요. 입력 소리, 클립보드 기록, 키보드에서 바꾼 언어 저장에만 쓰고, 이 앱은 네트워크를 사용하지 않아요."))
            }
            if model.fullAccessObserved {
                Label(L("전체 접근이 허용된 상태로 키보드가 실행됐어요."), systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            if model.saveFailed {
                Label(L("설정을 저장하지 못했어요. 앱 그룹 설정을 확인해 주세요."), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Section(L("입력")) {
                Picker(L("키보드 언어"), selection: $model.settings.typingLanguage) { Text(L("한국어")).tag("ko"); Text("English").tag("en") }
                    .accessibilityIdentifier("typing-language")
                Picker(L("한국어 배열"), selection: $model.settings.layout) { Text(L("두벌식")).tag("dubeolsik"); Text(L("천지인")).tag("cheonjiin"); Text(L("모아키")).tag("moaki") }
                    .accessibilityIdentifier("keyboard-layout")
                if model.settings.layout == "moaki" { Text(L("자음에서 드래그해 모음을 입력하세요. →ㅏ ←ㅓ ↑ㅗ ↓ㅜ ↗ㅣ ↘ㅡ")).font(.footnote).foregroundStyle(.secondary) }
                VStack(alignment: .leading) {
                    Text(L("키 높이 {0}", Int(model.settings.keyHeight)))
                    Slider(value: $model.settings.keyHeight, in: KeyboardSettings.keyHeights, step: 2).accessibilityLabel(L("키 높이"))
                }
                Toggle(L("진동"), isOn: $model.settings.haptics)
                Toggle(L("입력 소리"), isOn: $model.settings.sound)
            }
            Section {
                NavigationLink(L("단축어 {0}개", model.settings.shortcuts.count)) { ShortcutsView() }.accessibilityIdentifier("shortcuts")
                NavigationLink(L("자주 쓰는 문구 {0}개", model.settings.snippets.count)) { SnippetsView() }.accessibilityIdentifier("snippets")
                Toggle(L("클립보드 기록"), isOn: $model.settings.clipboardHistory)
            } header: { Text(L("텍스트 도구")) } footer: {
                Text(L("단축어를 입력하면 키보드 위에 바꿀 문구가 표시돼요. 클립보드 기록은 전체 접근이 필요하고, 키보드가 실행되는 동안 메모리에만 최근 10개를 보관해요."))
            }
            Section(L("입력해 보기")) {
                TextField(L("여기를 눌러 {0}로 입력해 보세요", AppInfo.name), text: $practice, axis: .vertical)
                    .lineLimit(3...6).autocorrectionDisabled().accessibilityIdentifier("practice")
            }
        }.navigationTitle(AppInfo.name)
    }
    private var setupSteps: [String] {[
        L("설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가를 열어요."),
        L("{0}를 선택해요.", AppInfo.name),
        L("입력 중에 지구본 키를 길게 눌러 {0}로 바꿔요.", AppInfo.name),
    ]}
}
