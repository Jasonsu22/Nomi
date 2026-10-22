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
                    .fixedSize()
            }
            .padding(.trailing, Space.s3)
            // At least the page column's inset, so the status lines up with page titles,
            // but never narrower than the logo and name.
            .frame(minWidth: leadingWidth, alignment: .leading)
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
            .tutorialTarget(.record)
        }
        .padding(.trailing, Space.s4)
        .frame(maxHeight: .infinity)
    }
}

/// Errors stay put, in red. A ready engine fades in, shows for two seconds, then fades out
/// in place, so it never slides over the name.
private struct HeaderStatus: View {
    var title: String
    var live: Bool
    var stays: Bool
    var isError: Bool
    var reduceMotion: Bool

    @State private var visible = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        StatusChip(title: title, live: live, isError: isError)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
            .onAppear { sync(stays: stays) }
            .onChange(of: title) { _, _ in sync(stays: stays) }
            .onChange(of: stays) { _, new in sync(stays: new) }
            .onDisappear { dismissTask?.cancel() }
    }

    private func sync(stays: Bool) {
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { visible = true }
        guard !stays else { return }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { visible = false }
        }
    }
}
