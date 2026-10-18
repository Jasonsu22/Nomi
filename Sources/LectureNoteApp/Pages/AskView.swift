import SwiftUI

struct AskView: View {
    var body: some View {
        VStack(spacing: Space.s3) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(AppColor.textSecondary)
            Text("针对一场会议提问")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("下一步会用这场的转写来回答，并附上可以跳转的时间。")
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
