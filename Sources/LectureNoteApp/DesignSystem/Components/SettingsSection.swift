import SwiftUI

/// A titled group of rows on one card, separated by inset dividers, with an optional footer
/// underneath, laid out like a group in macOS System Settings.
struct SettingsSection<Content: View, Footer: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.bottom, 2)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SettingsDivider() }
                        row
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            footer
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.s4)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.footer = EmptyView()
    }
}

extension SettingsSection {
    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }
}

/// One row: a title (and optional detail line) on the left, a control on the right.
struct SettingsRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
                if let detail {
                    Text(detail).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s3)
            trailing
        }
        .settingsRowPadding()
    }
}

/// A full-width "+ Add …" row at the end of a list.
struct SettingsAddRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(AppFont.body)
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsRowPadding()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain.clicking())
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
    }
}

/// The on/off switch used in every Settings row, at the System Settings size.
struct SettingsSwitch: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .clickCursor()
    }
}

extension View {
    /// The shared inner spacing of a Settings row, so every row has the same height and inset.
    func settingsRowPadding() -> some View {
        padding(.horizontal, Space.s4)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
    }
}
