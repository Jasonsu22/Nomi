import SwiftUI

struct RecordingLanguagePicker: View {
    @Binding var source: String
    @Binding var target: String

    var body: some View {
        Picker(tr("识别语言"), selection: $source) {
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
        Picker(tr("翻译为"), selection: $target) {
            Text(tr("不翻译")).tag("none")
            ForEach(LectureLanguages.supported, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
    }
}

struct RecordingSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text(tr("录制会议"))
                .font(AppFont.detailTitle)
            Form {
                LabeledContent(tr("输入源")) {
                    AudioInputPicker(inputs: model.audioInputs)
                }
                RecordingLanguagePicker(source: $model.recordingSourceLanguage, target: $model.recordingTargetLanguage)
            }
            .formStyle(.grouped)
            .frame(height: 180)
            if model.audioInputs.selectedDevice == nil, model.engine.readiness != .preview {
                Text(tr("请选择可用的音频输入设备。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(tr("取消")) { model.recordingSetupPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(tr("开始录制")) { model.startTranscription() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRecord)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 440)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.canvas)
    }
}
