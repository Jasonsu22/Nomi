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
            HeaderStatus(
                title: model.statusTitle,
                live: model.statusIsLive,
                stays: model.statusStays,
                isError: model.statusIsError,
                reduceMotion: reduceMotion
            )
            Spacer(minLength: Space.s3)
            SessionControl(
                session: model.engine.session,
                meter: model.engine.level,
                canStart: model.canStart,
                startTitle: model.recordingActionTitle,
                reduceMotion: reduceMotion,
                onStart: { model.performRecordingAction() },
                onStop: { model.stopTranscription() },
                onTogglePause: model.togglePause,
                onOpen: {
                    withAnimation(Motion.layout(reduceMotion)) { model.openLiveMeeting() }
                }
            )
        }
        .padding(.trailing, Space.s4)
        .frame(maxHeight: .infinity)
    }
}

/// Errors stay put, in red. A ready engine shows for two seconds, then the
/// words slide left and fade.
private struct HeaderStatus: View {
    var title: String
    var live: Bool
    var stays: Bool
    var isError: Bool
    var reduceMotion: Bool

    @State private var visible = false
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        StatusChip(title: title, live: live, isError: isError)
            .offset(x: offset)
            .opacity(visible ? opacity : 0)
            .accessibilityHidden(!visible)
            .onAppear { sync(title, stays: stays) }
            .onChange(of: title) { _, new in sync(new, stays: stays) }
            .onChange(of: stays) { _, new in sync(title, stays: new) }
            .onDisappear { dismissTask?.cancel() }
    }

    private func sync(_ title: String, stays: Bool) {
        dismissTask?.cancel()
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            visible = true
            offset = 0
            opacity = 1
        }
        guard !stays else { return }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                visible = false
                return
            }
            withAnimation(.easeInOut(duration: 0.32)) { offset = -20 }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
