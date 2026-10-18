import SwiftUI

struct TopBar: View {
    var model: AppModel
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: Space.s3) {
            BrandLogo(side: 20)
            Text("Nomi")
                .font(AppFont.secondary.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            StatusChip(title: model.statusTitle, live: model.statusIsLive)
            Spacer(minLength: Space.s3)
            SessionControl(
                session: model.engine.session,
                meter: model.engine.level,
                canStart: model.canStart,
                reduceMotion: reduceMotion,
                onStart: {
                    withAnimation(Motion.morph(reduceMotion)) {
                        model.startTranscription()
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
        .padding(.horizontal, Space.s4)
        .frame(height: 52)
        .background {
            AppColor.canvas
                .gesture(WindowDragGesture())
        }
    }
}
