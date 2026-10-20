import SwiftUI

struct SessionControl: View {
    var session: SessionState
    var meter: LevelMeter
    var canStart: Bool
    var startTitle: String
    var reduceMotion: Bool
    var onStart: () -> Void
    var onStop: () -> Void
    var onTogglePause: () -> Void
    /// Opens the meeting being recorded. The compact window already shows it and passes nil.
    var onOpen: (() -> Void)? = nil

    var body: some View {
        phaseControl
            // Tinted glass, not the interactive kind. The interactive hover tracker
            // crashes on macOS 26 when this control is replaced during the click.
            .glassEffect(.regular.tint(fill), in: Capsule())
            .clickCursor(enabled: session.phase == .listening || (session.phase == .idle && canStart))
    }

    private var listening: Bool {
        session.phase == .listening || session.phase == .stopping
    }

    private var fill: Color {
        listening ? AppColor.selection : AppColor.accent
    }

    private var ink: Color {
        listening ? AppColor.onSelection : AppColor.onAccent
    }

    private func hitCapsule<V: View>(_ content: V) -> some View {
        content
            .background(Color.white.opacity(0.001), in: Capsule())
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var phaseControl: some View {
        switch session.phase {
        case .idle:
            Button(action: onStart) {
                hitCapsule(label(title: startTitle, pulsing: false))
            }
            .buttonStyle(.plain.clicking())
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.4)
            .accessibilityLabel(startTitle)
        case .preparing:
            label(title: tr("准备中"), pulsing: true)
                .accessibilityLabel(tr("准备中"))
        case .listening:
            listeningControl
        case .stopping:
            Text(tr("正在保存"))
                .font(AppFont.secondary.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
                .frame(height: 40)
        }
    }

    private func label(title: String, pulsing: Bool) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "waveform")
                .symbolEffect(.pulse, options: .repeating, isActive: pulsing && !reduceMotion)
            Text(title)
        }
        .font(AppFont.secondary.weight(.semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var listeningControl: some View {
        HStack(spacing: 10) {
            if let onOpen {
                // A sibling of the pause and stop buttons, so those keep their own clicks.
                Button(action: onOpen) {
                    progress.contentShape(Rectangle())
                }
                .buttonStyle(.plain.clicking())
                .help(tr("回到正在录制的会议"))
                .accessibilityLabel(tr("回到正在录制的会议"))
            } else {
                progress
            }
            iconButton(
                systemName: session.isPaused ? "play.fill" : "pause.fill",
                label: session.isPaused ? tr("继续") : tr("暂停"),
                filled: false,
                action: onTogglePause
            )
            iconButton(systemName: "stop.fill", label: tr("停止"), filled: true, danger: true, action: onStop)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
    }

    private var progress: some View {
        HStack(spacing: 10) {
            DotWaveform(meter: meter, paused: session.isPaused, reduceMotion: reduceMotion)
                .foregroundStyle(ink)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(formatClock(session.elapsed))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                    .frame(width: 48, alignment: .leading)
            }
        }
    }

    private func iconButton(systemName: String, label: String, filled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? Color.white : ink)
                .frame(width: 22, height: 22)
                .background(danger ? Color.red : (filled ? AppColor.accent : AppColor.surface), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain.clicking())
        .accessibilityLabel(label)
    }
}
