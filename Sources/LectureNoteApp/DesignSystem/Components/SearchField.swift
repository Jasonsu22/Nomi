import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var prompt: String = "搜索会议、内容或分类"

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .focused(isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(AppColor.surface, in: Capsule())
    }
}
