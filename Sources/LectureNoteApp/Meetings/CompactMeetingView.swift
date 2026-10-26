import SwiftUI

struct CompactMeetingView: View {
    @Bindable var model: AppModel
    var meetingID: UUID
    var reduceMotion: Bool

    var body: some View {
        Group {
            if let meeting = model.meetings.first(where: { $0.id == meetingID }) {
                content(meeting)
            }
        }
    }

    private func content(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Always here, so a stopped meeting can continue recording without leaving this window.
            HStack {
                Spacer(minLength: 0)
                sessionControl
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s2) {
                Button {
                    withAnimation(Motion.layout(reduceMotion)) {
                        model.closeMeeting()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(AppColor.surface, in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .accessibilityLabel(tr("返回会议列表"))

                CategoryIcon(
                    symbol: model.category(for: meeting.categoryID)?.symbol ?? CategoryPalette.uncategorizedSymbol,
                    colorIndex: model.category(for: meeting.categoryID)?.colorIndex ?? CategoryPalette.uncategorizedIndex
                )
                Text(meeting.title.isEmpty ? tr("未命名会议") : meeting.title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Button {
                    withAnimation(MeetingWindowFrame.animation(reduceMotion: reduceMotion)) {
                        model.meetingCompact = false
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(AppColor.surface, in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .accessibilityLabel(tr("恢复窗口"))
                .help(tr("恢复窗口"))
            }
            DetailSidePanel(
                model: model,
                meeting: meeting,
                reduceMotion: reduceMotion,
                onClose: {},
                tabs: DetailTab.compactTabs,
                initialTab: .transcript,
                showsClose: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Over the older lines under the tabs, so the newest transcript at the bottom stays readable.
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if let popup = model.questionPopup, model.engine.session.phase != .idle {
                        QuestionPopupView(model: model, popup: popup, reduceMotion: reduceMotion, width: nil)
                            .id(popup.id)
                            .padding(.top, 40)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9), value: model.questionPopup?.id)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.canvas.ignoresSafeArea().gesture(WindowDragGesture()))
    }

    private var sessionControl: some View {
        SessionControl(
            session: model.engine.session,
            meter: model.engine.level,
            canStart: model.canStart,
            startTitle: model.recordingActionTitle,
            reduceMotion: reduceMotion,
            onStart: { model.performRecordingAction() },
            onStop: { model.stopTranscription() },
            onTogglePause: model.togglePause
        )
    }
}
