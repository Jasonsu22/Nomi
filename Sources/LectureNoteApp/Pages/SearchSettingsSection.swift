import SwiftUI

struct SearchSettingsSection: View {
    var model: AppModel
    @State private var editing: SearchVendor?

    var body: some View {
        SettingsSection(tr("联网搜索")) {
            ForEach(SearchVendor.allCases) { vendor in row(vendor) }
        } footer: {
            Text(tr("选择一个已配置的服务用于联网搜索。密钥保存在钥匙串里。"))
        }
        .sheet(item: $editing) { vendor in
            SearchProviderEditor(vendor: vendor, model: model)
        }
    }

    /// Click a configured row to use it; Set Up or Edit opens the editor, which also tests the connection.
    private func row(_ vendor: SearchVendor) -> some View {
        let ready = model.webSearch.isReady(vendor)
        let selected = model.webSearch.selected == vendor
        return HStack(spacing: Space.s3) {
            Button { model.webSearch.select(vendor) } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(selected ? AppColor.accent : AppColor.textSecondary.opacity(ready ? 1 : 0.4))
                    ProviderLogo(file: vendor.logoFile)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(vendor.title).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
                            if vendor == .tavily {
                                Text(tr("推荐"))
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(AppColor.accentSoft, in: Capsule())
                            }
                        }
                        Text(model.webSearch.status(for: vendor))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain.clicking())
            .disabled(!ready)
            Button(ready ? tr("编辑") : tr("配置")) { editing = vendor }
                .clickCursor()
        }
        .settingsRowPadding()
    }
}

private struct SearchProviderEditor: View {
    let vendor: SearchVendor
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var baseURL = ""
    @State private var testing = false
    @State private var note: String?
    @State private var noteIsError = false
    @State private var confirmingDelete = false

    init(vendor: SearchVendor, model: AppModel) {
        self.vendor = vendor
        self.model = model
        _baseURL = State(initialValue: model.webSearch.endpoint(for: vendor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                ProviderLogo(file: vendor.logoFile, side: 22)
                Text(vendor.title).font(AppFont.sectionTitle)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vendor.needsBaseURL
                         ? tr("SearXNG 没有统一账号。按文档搭好自己的服务，把地址填在下面。")
                         : tr("先在这个页面注册账号，创建 API 密钥，再粘贴到下面。"))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(vendor.accountURL.absoluteString, destination: vendor.accountURL)
                        .font(AppFont.caption)
                        .clickCursor()
                }
                if vendor.needsBaseURL {
                    field(tr("搜索地址")) {
                        TextField("http://127.0.0.1:8080", text: $baseURL)
                    }
                }
                field(tr("API 密钥")) {
                    SecureField(tr("API 密钥"), text: $key)
                }
                if vendor.needsBaseURL {
                    Text(tr("密钥可留空。"))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            if let note {
                Text(note)
                    .font(AppFont.caption)
                    .foregroundStyle(noteIsError ? Color.red : AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(tr("测试连接")) { Task { await test() } }
                    .clickCursor()
                    .disabled(testing)
                if model.webSearch.isReady(vendor) {
                    Button(tr("删除"), role: .destructive) { confirmingDelete = true }
                        .clickCursor()
                }
                if testing { ProgressView().controlSize(.small) }
                Spacer()
                Button(tr("取消")) { dismiss() }
                    .clickCursor()
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) { save() }
                    .buttonStyle(.borderedProminent.clicking())
                    .disabled(testing)
            }
        }
        .padding(Space.s5)
        .frame(width: 640)
        .onAppear { key = (try? SearchKeychain.read(vendor)) ?? "" }
        .alert(trf("删除 %@ 的搜索配置？", vendor.title), isPresented: $confirmingDelete) {
            Button(tr("删除"), role: .destructive) { remove() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("钥匙串里的密钥和保存的地址会被清掉。"))
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: true, vertical: false)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        do {
            try model.webSearch.save(vendor: vendor, key: key, baseURL: baseURL)
            dismiss()
        } catch {
            note = error.localizedDescription
            noteIsError = true
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let count = try await model.webSearch.test(vendor: vendor, key: key, baseURL: baseURL)
            note = trf("连上了，返回了 %d 条结果", count)
            noteIsError = false
        } catch {
            note = error.localizedDescription
            noteIsError = true
        }
    }

    private func remove() {
        do {
            try model.removeSearch(vendor)
            dismiss()
        } catch {
            note = error.localizedDescription
            noteIsError = true
        }
    }
}
