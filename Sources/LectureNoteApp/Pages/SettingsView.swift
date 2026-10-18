import AVFoundation
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage(InterfaceLanguage.key) private var interfaceLanguage = InterfaceLanguage.system.rawValue
    @AppStorage(InterfaceAppearance.key) private var appearance = InterfaceAppearance.system.rawValue

    var body: some View {
        PageScaffold(title: tr("设置")) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(spacing: 0) {
                        settingRow(tr("界面语言")) {
                            Picker(tr("界面语言"), selection: $interfaceLanguage) {
                                ForEach(InterfaceLanguage.allCases) { language in
                                    Text(language.title).tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .selectedTextPickerWidth((InterfaceLanguage(rawValue: interfaceLanguage) ?? .system).title)
                        }
                        divider
                        settingRow(tr("外观")) {
                            Picker(tr("外观"), selection: $appearance) {
                                ForEach(InterfaceAppearance.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .labelsHidden()
                            .selectedTextPickerWidth((InterfaceAppearance(rawValue: appearance) ?? .system).title)
                        }
                        divider
                        row(tr("麦克风权限"), microphone)
                    }
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                    LocalModelsSection(model: model)
                    LLMSettingsSection(model: model)

                    HStack(spacing: Space.s3) {
                        BrandLogo(side: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nomi")
                                .font(AppFont.sectionTitle)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(tr("本机讲座笔记"))
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    Text(tr("识别和翻译在本机运行。提问和摘要可选择本地模型或 API。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .pageColumn(maxWidth: 760)
                .padding(.bottom, Space.s7)
            }
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
            Spacer()
            content().font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    private func row(_ title: String, _ value: String) -> some View {
        settingRow(title) { Text(value) }
    }

    private var microphone: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: tr("已允许")
        case .denied: tr("已拒绝")
        default: tr("开始时询问")
        }
    }

    private var divider: some View {
        Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
    }
}

struct HelpView: View {
    var body: some View {
        PageScaffold(title: tr("帮助")) {
            VStack(alignment: .leading, spacing: Space.s4) {
                note(tr("按下右上角的「开始转录」，Nomi 会听麦克风，在本机识别，并翻译成目标语言。"))
                note(tr("正在说的字是浅色，提交之后在原位变深，译文接在这一段下面。"))
                note(tr("往上翻之后，右下角会出现「回到最新」。"))
            }
            .pageColumn(maxWidth: 760)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body)
            .foregroundStyle(AppColor.textPrimary)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
