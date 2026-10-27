import SwiftUI
import KeyboardCore

struct ShortcutsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var editing: String?
    @State private var problem: String?
    var body: some View {
        List {
            Section {
                TextField(L("단축어 (예: ㅂㄱ)"), text: $trigger).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("shortcut-trigger")
                TextField(L("바꿀 문구"), text: $expansion, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("shortcut-expansion")
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                Button(L(editing == nil ? "추가" : "저장"), action: save).disabled(trigger.isEmpty || expansion.isEmpty)
                if editing != nil { Button(L("취소"), role: .cancel, action: reset) }
            }
            Section {
                ForEach(model.settings.shortcuts, id: \.trigger) { item in
                    Button { editing = item.trigger; trigger = item.trigger; expansion = item.expansion; problem = nil } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.trigger).foregroundStyle(.primary)
                            Text(item.expansion).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }.onDelete { model.settings.shortcuts.remove(atOffsets: $0); reset() }
            } footer: { Text(L("단축어는 공백 없이 {0}자까지, 문구는 {1}자까지 입력할 수 있어요.", TextShortcuts.maxTrigger, TextShortcuts.maxExpansion)) }
        }.navigationTitle(L("단축어")).navigationBarTitleDisplayMode(.inline)
    }
    private func save() {
        if let message = TextShortcuts.validate(trigger: trigger, expansion: expansion, existing: model.settings.shortcuts, replacing: editing) { problem = L(message); return }
        let value = TextShortcut(trigger: trigger, expansion: expansion)
        if let editing, let index = model.settings.shortcuts.firstIndex(where: { $0.trigger == editing }) { model.settings.shortcuts[index] = value }
        else { model.settings.shortcuts.append(value) }
        reset()
    }
    private func reset() { editing = nil; trigger = ""; expansion = ""; problem = nil }
}

struct SnippetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var editing: String?
    @State private var problem: String?
    var body: some View {
        List {
            Section {
                TextField(L("문구"), text: $text, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("snippet-text")
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                Button(L(editing == nil ? "추가" : "저장"), action: save).disabled(text.isEmpty)
                if editing != nil { Button(L("취소"), role: .cancel, action: reset) }
            }
            Section {
                ForEach(model.settings.snippets, id: \.self) { item in
                    Button { editing = item; text = item; problem = nil } label: { Text(item).foregroundStyle(.primary).lineLimit(3) }
                }
                .onDelete { model.settings.snippets.remove(atOffsets: $0); reset() }
                .onMove { model.settings.snippets.move(fromOffsets: $0, toOffset: $1) }
            } footer: { Text(L("키보드 위의 문구 버튼을 누르면 목록에서 골라 입력할 수 있어요. 최대 {0}개까지 저장해요.", Snippets.maxCount)) }
        }.navigationTitle(L("자주 쓰는 문구")).navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
    }
    private func save() {
        if let message = Snippets.validate(text, existing: model.settings.snippets, replacing: editing) { problem = L(message); return }
        if let editing, let index = model.settings.snippets.firstIndex(of: editing) { model.settings.snippets[index] = text }
        else { model.settings.snippets.append(text) }
        reset()
    }
    private func reset() { editing = nil; text = ""; problem = nil }
}
