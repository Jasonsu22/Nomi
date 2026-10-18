import SwiftUI

struct StatsView: View {
    var meetings: [Meeting]

    var body: some View {
        PageScaffold(title: "统计") {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s4) {
                    card(value: "\(meetings.count)", unit: "场", label: "会议")
                    card(value: formatDuration(meetings.reduce(0) { $0 + $1.duration }), unit: "", label: "时长")
                    card(value: "\(meetings.reduce(0) { $0 + $1.characterCount })", unit: "字", label: "转写")
                }
                Text("示例数据。接上录音之后，这里会计这场课的时长和字数。")
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, Space.s6)
            .frame(maxWidth: 880)
        }
    }

    private func card(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColor.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
