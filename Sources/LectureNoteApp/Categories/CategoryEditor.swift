import SwiftUI

struct CategoryDraft: Equatable {
    var name = ""
    var colorIndex = 0
    var symbol = CategorySymbols.all[0]
}

struct CategoryEditor: View {
    var title: String
    @Binding var draft: CategoryDraft
    var onSubmit: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            TextField(tr("分类名称"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            Text(tr("颜色"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: 8) {
                ForEach(0..<CategoryPalette.swatches.count, id: \.self) { index in
                    Button {
                        draft.colorIndex = index
                    } label: {
                        Circle()
                            .fill(CategoryPalette.ink(index))
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay {
                                if draft.colorIndex == index {
                                    Circle().strokeBorder(AppColor.textPrimary, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trf("颜色 %d", index + 1))
                }
            }
            Text(tr("图标"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CategorySymbols.all, id: \.self) { symbol in
                    Button {
                        draft.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(draft.symbol == symbol ? AppColor.onSelection : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                draft.symbol == symbol ? AppColor.selection : AppColor.surfaceInset,
                                in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            Button(action: submit) {
                Text(tr("完成"))
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(canSubmit ? AppColor.accent : AppColor.outline, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var canSubmit: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}
