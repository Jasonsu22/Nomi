import SwiftUI

struct TopBar: View {
    var model: AppModel
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            bar(leadingWidth: Rail.width + PageColumnLayout.leadingInset(in: proxy.size.width - Rail.width))
        }
        .frame(height: 52)
        .background {
            AppColor.canvas
                .gesture(WindowDragGesture())
        }
    }

    private func bar(leadingWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                BrandLogo(side: 32)
                    .frame(width: Rail.width - Space.s4)
                    .padding(.leading, Space.s2)
                Text("Nomi")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(width: leadingWidth, alignment: .leading)
            StatusChip(title: model.statusTitle, live: model.statusIsLive)
            Spacer(minLength: Space.s3)
            SessionControl(
                session: model.engine.session,
                meter: model.engine.level,
                canStart: model.canStart,
                reduceMotion: reduceMotion,
                onStart: {
                    withAnimation(Motion.morph(reduceMotion)) {
                        model.prepareRecording()
                    }
                },
                onStop: {
                    withAnimation(Motion.morph(reduceMotion)) {
                        model.stopTranscription()
                    }
                },
                onTogglePause: model.togglePause
            )
        }
        .padding(.trailing, Space.s4)
        .frame(maxHeight: .infinity)
    }
}
