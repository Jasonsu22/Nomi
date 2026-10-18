import SwiftUI

struct RecordingLanguagePicker: View {
    @Binding var source: String
    @Binding var target: String

    var body: some View {
        inputPicker
        translationPicker
    }

    fileprivate var inputPicker: some View {
        Picker(tr("输入语言"), selection: $source) {
            Text(languageName(LectureLanguages.automatic)).tag(LectureLanguages.automatic)
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
    }

    fileprivate var translationPicker: some View {
        Picker(tr("目标翻译语言"), selection: $target) {
            Text(tr("不翻译")).tag("none")
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
    }
}

struct RecordingSetupView: View {
    @Bindable var model: AppModel
    @State private var title = tr("未命名会议")
    @State private var categoryID: UUID?
    @State private var startedAt = Date()
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
                        // titleFocused = false here moves focus on to the date field.
                        .background(OutsideClickObserver(isActive: titleFocused) {})
                }
                divider
                settingRow(tr("开始时间")) {
                    DatePicker(tr("开始时间"), selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
                divider
                settingRow(tr("分类")) {
                    Picker(tr("分类"), selection: $categoryID) {
                        Text(tr("未分类")).tag(nil as UUID?)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .labelsHidden()
                    .selectedTextPickerWidth(model.category(for: categoryID)?.name ?? tr("未分类"))
                }
                divider
                settingRow(tr("输入源")) {
                    AudioInputPicker(inputs: model.audioInputs, fitsSelectedText: true)
                }
                divider
                settingRow(tr("输入语言")) {
                    languages.inputPicker
                        .labelsHidden()
                        .selectedTextPickerWidth(languageName(model.recordingSourceLanguage))
                }
                divider
                settingRow(tr("目标翻译语言")) {
                    languages.translationPicker
                        .labelsHidden()
                        .selectedTextPickerWidth(model.recordingTargetLanguage == "none" ? tr("不翻译") : languageName(model.recordingTargetLanguage))
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
                Spacer()
                Button(tr("取消")) { model.cancelRecordingSetup() }
                    .keyboardShortcut(.cancelAction)
                Button(model.recordingResumeID == nil ? tr("开始录制") : tr("继续录制")) {
                    model.startTranscription(title: title, categoryID: categoryID, startedAt: startedAt)
                }
                    .buttonStyle(.borderedProminent)
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
                startedAt = meeting.startedAt
            }
        }
    }

    private var languages: RecordingLanguagePicker {
        RecordingLanguagePicker(source: $model.recordingSourceLanguage, target: $model.recordingTargetLanguage)
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
