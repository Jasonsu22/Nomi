import SwiftUI

struct SettingsView: View {
    var body: some View {
        PageScaffold(title: "设置") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(spacing: 0) {
                        row("输入源", "麦克风")
                        divider
                        row("源语言", "中文")
                        divider
                        row("目标语言", "英文")
                        divider
                        row("外观", "跟随系统")
                        divider
                        row("模型目录", "~/.OminiX/models")
                        divider
                        row("麦克风权限", "预览中，尚未申请")
                    }
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                    HStack(spacing: Space.s3) {
                        BrandLogo(side: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LectureNote")
                                .font(AppFont.sectionTitle)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("本机讲座笔记")
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    Text("这一步只回放示例讲座，用来看界面。识别、翻译和录音还没接上。")
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .pageColumn(maxWidth: 760)
                .padding(.bottom, Space.s7)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text(value)
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: 1)
            .padding(.leading, Space.s4)
    }
}

struct HelpView: View {
    var body: some View {
        PageScaffold(title: "帮助") {
            VStack(alignment: .leading, spacing: Space.s4) {
                note("按下右上角的「开始转录」，会回放一场示例讲座，方便先看动画。")
                note("正在说的字是浅色，提交之后在原位变深，译文接在这一段下面。")
                note("往上翻之后，右下角会出现「回到最新」。")
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
