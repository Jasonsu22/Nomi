import SwiftUI

struct PromptSettingsSection: View {
    var model: AppModel
    @State private var editingSystem = false
    @State private var editingSkill: PromptSkill?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(tr("技能"))
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            VStack(spacing: 0) {
                Button { editingSystem = true } label: {
                    HStack {
                        Text(tr("默认系统提示词"))
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(model.prompts.isSystemCustomized ? tr("已修改") : tr("默认"))
                                .font(AppFont.secondary.weight(.medium))
                                .foregroundStyle(AppColor.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain.clicking())
                Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
                HStack {
                    Text(tr("默认回复语言"))
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    replyLanguageMenu
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            VStack(spacing: 0) {
                ForEach(model.prompts.skills) { skill in
                    skillRow(skill)
                    Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
                }
                Button {
                    editingSkill = PromptSkill()
                } label: {
                    Label(tr("添加技能"), systemImage: "plus")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain.clicking())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            Text(tr("启用的技能会和系统提示词一起发给模型。"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .sheet(isPresented: $editingSystem) {
            SystemPromptEditor(prompts: model.prompts)
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditor(prompts: model.prompts, skill: skill)
        }
    }

    private var replyLanguageMenu: some View {
        let options = [(PromptPreferences.followInterface, tr("跟随界面"))]
            + LectureLanguages.supported.map { ($0, languageName($0)) }
        let current = model.prompts.replyLanguageTitle
        return Menu {
            Picker("", selection: Binding(
                get: { model.prompts.replyLanguage },
                set: { model.prompts.setReplyLanguage($0) }
            )) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(current)
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain.clicking())
        .menuIndicator(.hidden)
        .fixedSize()
        .clickCursor()
    }

    private func skillRow(_ skill: PromptSkill) -> some View {
        HStack(spacing: Space.s3) {
            Button { editingSkill = skill } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(skill.body)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain.clicking())
            Toggle(isOn: Binding(
                get: { skill.enabled },
                set: { model.prompts.setEnabled($0, id: skill.id) }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .clickCursor()
            .accessibilityLabel(trf("启用 %@", skill.name))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }
}

private struct SystemPromptEditor: View {
    var prompts: PromptPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var confirming = false

    init(prompts: PromptPreferences) {
        self.prompts = prompts
        _draft = State(initialValue: prompts.systemText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(tr("默认系统提示词"))
                .font(AppFont.sectionTitle)
            TextEditor(text: $draft)
                .font(AppFont.secondary)
                .scrollContentBackground(.hidden)
                .padding(Space.s3)
                .frame(height: 320)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            Text(tr("回复语言会加在系统提示词后面。系统提示词只有一份。"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            HStack {
                Button(tr("恢复默认")) { draft = ChatContext.defaultSystemText }
                    .clickCursor()
                Spacer()
                Button(tr("取消")) { dismiss() }
                    .clickCursor()
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) { requestSave() }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 560)
        .alert(tr("修改系统提示词？"), isPresented: $confirming) {
            Button(tr("仍然保存")) {
                prompts.saveSystem(draft)
                dismiss()
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("系统提示词只有一份。改动后，身份、引用和阅读资料等功能可能会失效。"))
        }
    }

    private func requestSave() {
        let trimmed = draft
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == ChatContext.defaultSystemText {
            prompts.saveSystem(trimmed)
            dismiss()
        } else {
            confirming = true
        }
    }
}

private struct SkillEditor: View {
    var prompts: PromptPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PromptSkill
    @State private var error: String?
    @State private var confirmingDelete = false
    private let isNew: Bool

    init(prompts: PromptPreferences, skill: PromptSkill) {
        self.prompts = prompts
        _draft = State(initialValue: skill)
        isNew = !prompts.skills.contains { $0.id == skill.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(tr("技能"))
                .font(AppFont.sectionTitle)
            TextField(tr("技能名称"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $draft.body)
                .font(AppFont.secondary)
                .scrollContentBackground(.hidden)
                .padding(Space.s3)
                .frame(height: 180)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if draft.body.isEmpty {
                        Text(tr("写下这段技能要模型怎么做。"))
                            .font(AppFont.secondary)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s3 + 8)
                            .allowsHitTesting(false)
                    }
                }
            if let error {
                Text(error)
                    .font(AppFont.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if !isNew {
                    Button(tr("删除"), role: .destructive) { confirmingDelete = true }
                        .clickCursor()
                        .foregroundStyle(.red)
                }
                Spacer()
                Button(tr("取消")) { dismiss() }
                    .clickCursor()
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) { save() }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 520)
        .alert(tr("删除技能？"), isPresented: $confirmingDelete) {
            Button(tr("删除"), role: .destructive) {
                prompts.delete(draft.id)
                dismiss()
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("删除后，提问和摘要不会再使用这段说明。"))
        }
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !body.isEmpty else {
            error = tr("请填写技能名称和内容。")
            return
        }
        draft.name = name
        draft.body = body
        prompts.upsert(draft)
        dismiss()
    }
}
