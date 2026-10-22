import SwiftUI

struct RecordingLanguagePicker: View {
    @Binding var source: String
    @Binding var target: String

    var body: some View {
        inputPicker
        translationPicker
    }

    private var inputPicker: some View {
        Picker(tr("输入语言"), selection: $source) {
            Text(languageName(LectureLanguages.automatic)).tag(LectureLanguages.automatic)
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
        .clickCursor()
    }

    private var translationPicker: some View {
        Picker(tr("目标翻译语言"), selection: $target) {
            Text(tr("不翻译")).tag("none")
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
        .clickCursor()
    }
}

struct RecordingSetupView: View {
    @Bindable var model: AppModel
    @State private var title = tr("未命名会议")
    @State private var categoryID: UUID?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text(model.recordingResumeID == nil ? tr("录制会议") : tr("继续录制"))
                .font(AppFont.detailTitle)
            VStack(spacing: 0) {
                settingRow(tr("会议标题")) {
                    TextField(tr("未命名会议"), text: $title)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 240)
                        .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
                        // The observer clears the first responder itself. Setting
                        // titleFocused = false here moves focus on to the next control.
                        .background(OutsideClickObserver(isActive: titleFocused) {})
                }
                divider
                settingRow(tr("分类")) {
                    SettingsPopUp(
                        selection: $categoryID,
                        options: [(nil as UUID?, tr("未分类"))] + model.categories.map { (Optional($0.id), $0.name) }
                    )
                    .accessibilityLabel(tr("分类"))
                }
                divider
                settingRow(tr("输入源")) {
                    AudioInputPicker(inputs: model.audioInputs, fitsSelectedText: true)
                }
                divider
                settingRow(tr("输入语言")) {
                    SettingsPopUp(
                        selection: $model.recordingSourceLanguage,
                        options: [(LectureLanguages.automatic, languageName(LectureLanguages.automatic))] + LectureLanguages.supported.map { ($0, languageName($0)) }
                    )
                    .accessibilityLabel(tr("输入语言"))
                }
                divider
                settingRow(tr("目标翻译语言")) {
                    SettingsPopUp(
                        selection: $model.recordingTargetLanguage,
                        options: [("none", tr("不翻译"))] + LectureLanguages.supported.map { ($0, languageName($0)) }
                    )
                    .accessibilityLabel(tr("目标翻译语言"))
                }
            }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if model.audioInputs.selectedDevice == nil, model.engine.readiness != .preview {
                Text(tr("请选择可用的音频输入设备。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
            }
            HStack {
                Button(tr("取消")) { model.cancelRecordingSetup() }
                    .clickCursor()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.recordingResumeID == nil ? tr("开始录制") : tr("继续录制")) {
                    model.startTranscription(title: title, categoryID: categoryID)
                }
                    .buttonStyle(.borderedProminent.clicking())
                    .disabled(!model.canRecord)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 440)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.canvas)
        .onAppear {
            if let meeting = model.recordingSetupMeeting {
                title = meeting.title
                categoryID = meeting.categoryID
            }
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Space.s3) {
            Text(label).font(AppFont.body)
            Spacer(minLength: Space.s2)
            content().font(AppFont.secondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var divider: some View {
        Rectangle().fill(AppColor.separator).frame(height: 1).padding(.horizontal, Space.s4)
    }
}
