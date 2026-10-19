import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case info = "信息"
    case ask = "提问"
    case summary = "摘要"
    case sources = "资料"

    var id: String { rawValue }
}

struct DetailSidePanel: View {
    @Bindable var model: AppModel
    var meeting: Meeting
    var reduceMotion: Bool
    var onPreferredSideWidth: (CGFloat) -> Void = { _ in }
    var onClose: () -> Void
    @State private var tab: DetailTab = .info
    @State private var confirmingDelete = false
    @State private var importingSources = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                ForEach(DetailTab.allCases) { item in
                    Button {
                        withAnimation(Motion.page(reduceMotion)) {
                            tab = item
                        }
                    } label: {
                        Text(tr(item.rawValue))
                            .font(AppFont.caption.weight(.medium))
                            .foregroundStyle(tab == item ? AppColor.onSelection : AppColor.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background {
                                if tab == item {
                                    Capsule()
                                        .fill(AppColor.selection)
                                        .matchedGeometryEffect(id: "detail-tab", in: tabNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain.clicking())
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain.clicking())
                .accessibilityLabel(tr("关闭侧栏"))
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            Group {
                switch tab {
                case .info:
                    info
                case .ask:
                    AskView(model: model, anchorMeetingID: meeting.id) { shown in
                        if shown { onPreferredSideWidth(640) }
                    }
                case .summary:
                    MeetingAssistantPanel(model: model, meeting: meeting, summary: true)
                case .sources:
                    sources
                }
            }
            .id(tab)
            .transition(.pageEnter(reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipped()
        .onChange(of: tab) { _, newValue in
            if newValue == .ask { onPreferredSideWidth(480) }
        }
        .alert(tr("删除这场会议？"), isPresented: $confirmingDelete) {
            Button(tr("删除"), role: .destructive) {
                let id = meeting.id
                Task { @MainActor in
                    withAnimation(Motion.layout(reduceMotion)) {
                        model.deleteMeeting(id)
                    }
                }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("转写会一起删掉。"))
        }
        .fileImporter(isPresented: $importingSources, allowedContentTypes: SourceStore.allowedTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            model.importLinkedSources(urls, meetingID: meeting.id)
        }
    }

    private var info: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(spacing: 0) {
                    categoryRow
                    hairline
                    durationRow
                    hairline
                    infoRow(tr("字数"), "\(meeting.characterCount)")
                }
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

                Button {
                model.export([meeting])
            } label: {
                Text(tr("导出 Markdown"))
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(AppColor.surfaceInset, in: Capsule())
            }
            .buttonStyle(.plain.clicking())

            if !meeting.isLive {
                Button {
                    confirmingDelete = true
                } label: {
                    Text(tr("删除会议"))
                        .font(AppFont.secondary.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain.clicking())
                .disabled(model.assistantStates[meeting.id]?.isGenerating == true)
            }
            }
            .padding(Space.s4)
        }
    }

    private var linkedSources: [KnowledgeSource] {
        model.linkedSources(for: meeting.id)
    }

    private var linkableSources: [KnowledgeSource] {
        let linked = Set(linkedSources.map(\.id))
        return model.sources.filter { source in
            !linked.contains(source.id) && (source.categoryID == meeting.categoryID || source.categoryID == nil)
        }
    }

    private var sources: some View {
        ScrollView {
            materials
                .padding(Space.s4)
        }
    }

    private var materials: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(tr("资料"))
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if !linkableSources.isEmpty {
                    Menu {
                        ForEach(linkableSources) { source in
                            Button(source.title) {
                                model.linkSource(source.id, to: meeting.id)
                            }
                        }
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .clickCursor()
                    .help(tr("关联已有资料"))
                }
            }
            if linkedSources.isEmpty {
                Text(tr("导入 PDF 或文档，提问时会一并阅读，并放进这个分类的资料库。"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(linkedSources) { source in
                        HStack(spacing: Space.s2) {
                            Image(systemName: source.fileName.lowercased().hasSuffix("pdf") ? "doc.richtext" : "doc")
                                .foregroundStyle(AppColor.textSecondary)
                            Text(source.title)
                                .font(AppFont.secondary)
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Space.s2)
                            Button {
                                model.unlinkSource(source.id, from: meeting.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            .buttonStyle(.plain.clicking())
                            .help(tr("取消关联"))
                        }
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 8)
                    }
                }
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            Button {
                importingSources = true
            } label: {
                Text(tr("添加资料"))
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(AppColor.surfaceInset, in: Capsule())
            }
            .buttonStyle(.plain.clicking())
        }
    }

    private var categoryRow: some View {
        HStack {
            Text(tr("分类"))
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
            Button(tr("未分类")) {
                model.assign(meeting: meeting.id, category: nil)
            }
            ForEach(model.categories) { category in
                Button(category.name) {
                    model.assign(meeting: meeting.id, category: category.id)
                }
            }
        } label: {
            Text(model.categoryName(for: meeting) ?? tr("未分类"))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .clickCursor()
    }

    private var durationRow: some View {
        Group {
            if meeting.isLive {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    infoRow(tr("时长"), formatClock(model.engine.session.elapsed))
                }
            } else {
                infoRow(tr("时长"), formatDuration(meeting.duration))
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

}
