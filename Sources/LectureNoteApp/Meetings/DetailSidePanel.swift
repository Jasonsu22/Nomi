import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case info = "信息"
    case ask = "提问"
    case summary = "摘要"

    var id: String { rawValue }
}

struct DetailSidePanel: View {
    @Bindable var model: AppModel
    var meeting: Meeting
    var reduceMotion: Bool
    var onClose: () -> Void
    @State private var tab: DetailTab = .info
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                ForEach(DetailTab.allCases) { item in
                    Button {
                        withAnimation(Motion.page(reduceMotion)) {
                            tab = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(AppFont.secondary.weight(tab == item ? .semibold : .regular))
                            .foregroundStyle(tab == item ? AppColor.textPrimary : AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭侧栏")
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            Group {
                switch tab {
                case .info:
                    info
                case .ask:
                    placeholder("提问会在接上 Qwen3.5-2B 之后可用。回答会附上这段话的时间。")
                case .summary:
                    placeholder("摘要会在接上模型之后可用。")
                }
            }
            .id(tab)
            .transition(.pageEnter(reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipped()
        .alert("删除这场会议？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) {
                model.deleteMeeting(meeting.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("转写会一起删掉。")
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(spacing: 0) {
                categoryRow
                hairline
                infoRow("输入源", meeting.source.title)
                hairline
                infoRow("语言", "\(languageName(meeting.sourceLanguage)) → \(languageName(meeting.targetLanguage))")
                hairline
                durationRow
                hairline
                infoRow("字数", "\(meeting.characterCount)")
            }
            .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

            Button {
                model.export([meeting])
            } label: {
                Text("导出 Markdown")
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(AppColor.surfaceInset, in: Capsule())
            }
            .buttonStyle(.plain)

            if !meeting.isLive {
                Button {
                    confirmingDelete = true
                } label: {
                    Text("删除会议")
                        .font(AppFont.secondary.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
    }

    private var categoryRow: some View {
        HStack {
            Text("分类")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            categoryMenu
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 12)
    }

    private var categoryMenu: some View {
        Menu {
            Button("未分类") {
                model.assign(meeting: meeting.id, category: nil)
            }
            ForEach(model.categories) { category in
                Button(category.name) {
                    model.assign(meeting: meeting.id, category: category.id)
                }
            }
        } label: {
            Text(model.categoryName(for: meeting) ?? "未分类")
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var durationRow: some View {
        Group {
            if meeting.isLive {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    infoRow("时长", formatClock(model.engine.session.elapsed))
                }
            } else {
                infoRow("时长", formatDuration(meeting.duration))
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
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
        .padding(.vertical, 12)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: 1)
            .padding(.leading, Space.s4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(AppFont.secondary)
            .foregroundStyle(AppColor.textSecondary)
            .lineSpacing(4)
            .padding(Space.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
