import SwiftUI

struct SourcesView: View {
    var meetings: [Meeting]

    var body: some View {
        PageScaffold(title: "资料") {
            ScrollView {
                VStack(spacing: Space.s3) {
                    ForEach(meetings) { meeting in
                        HStack(spacing: Space.s3) {
                            Image(systemName: "waveform")
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meeting.title)
                                    .font(AppFont.secondary.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("转写 \(meeting.paragraphs.count) 段 · 音频尚未录制")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(Space.s4)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s7)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
