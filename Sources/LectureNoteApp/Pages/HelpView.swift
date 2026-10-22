import AppKit
import SwiftUI

/// App information, the quick tutorial, and how to reach us.
struct HelpView: View {
    var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var checksAutomatically = true

    static let contactEmail = "jasonsu210@gmail.com"

    var body: some View {
        PageScaffold(title: tr("帮助"), columnWidth: PageColumnLayout.narrowWidth) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    appInfo
                    helpCard
                    updatesSection
                }
                .pageColumn(maxWidth: PageColumnLayout.narrowWidth)
                .padding(.bottom, Space.s7)
            }
        }
    }

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
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
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(tr("帮助"), systemImage: "questionmark.circle")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 14)
            Divider().padding(.horizontal, Space.s4)
            row(title: tr("开始快速教程"), detail: tr("用几步认识主要按钮。")) {
                withAnimation(Motion.layout(reduceMotion)) { model.startTutorial() }
            }
            Divider().padding(.horizontal, Space.s4)
            contactRow
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Version, automatic checks and a manual check. Hidden when Sparkle is not running (`swift run`).
    @ViewBuilder
    private var updatesSection: some View {
        if model.updater.isAvailable {
            SettingsSection(tr("更新")) {
                SettingsRow(tr("当前版本")) {
                    Text(model.updater.version)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
                SettingsRow(tr("自动检查更新"), detail: tr("每天检查一次，有新版本时会提示你安装。")) {
                    SettingsSwitch(label: tr("自动检查更新"), isOn: Binding(
                        get: { checksAutomatically },
                        set: { value in
                            checksAutomatically = value
                            model.updater.automaticallyChecks = value
                        }
                    ))
                }
                SettingsRow(tr("检查更新")) {
                    Button(tr("立即检查")) { model.updater.checkForUpdates() }
                        .clickCursor()
                        .disabled(!model.updater.canCheck)
                }
            }
            .onAppear { checksAutomatically = model.updater.automaticallyChecks }
        }
    }

    private var contactRow: some View {
        row(title: tr("联系我们"), detail: Self.contactEmail, action: openMail)
            .help(tr("用邮件联系我们"))
    }

    private func row(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(detail)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain.clicking())
    }

    /// Opens a new message in the default mail app, addressed to us with a short template.
    private func openMail() {
        if let url = Self.mailURL() { NSWorkspace.shared.open(url) }
    }

    static func mailURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contactEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: tr("Nomi 反馈")),
            URLQueryItem(name: "body", value: mailBody()),
        ]
        return components.url
    }

    static func mailBody() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        return [
            tr("你好，"),
            "",
            tr("主题："),
            "",
            tr("发生了什么："),
            "",
            tr("复现步骤："),
            "1. ",
            "",
            "—",
            "Nomi \(version) (\(build))",
            "macOS \(system)",
        ].joined(separator: "\n")
    }
}
