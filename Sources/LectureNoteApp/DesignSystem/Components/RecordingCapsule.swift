import SwiftUI

struct SessionControl: View {
    var session: SessionState
    var meter: LevelMeter
    var canStart: Bool
    var reduceMotion: Bool
    var onStart: () -> Void
    var onStop: () -> Void
    var onTogglePause: () -> Void
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            control
                .background(fill, in: Capsule())
                .glassEffect(.clear.interactive(session.phase == .idle), in: Capsule())
                .glassEffectID("session", in: glassNamespace)
        }
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

    @ViewBuilder
    private var control: some View {
        switch session.phase {
        case .idle:
            Button(action: onStart) {
                label(title: tr("开始转录"), pulsing: false)
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.4)
            .accessibilityLabel(tr("开始转录"))
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
            DotWaveform(meter: meter, paused: session.isPaused, reduceMotion: reduceMotion)
                .foregroundStyle(ink)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(formatClock(session.elapsed))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                    .frame(width: 48, alignment: .leading)
            }
            iconButton(
                systemName: session.isPaused ? "play.fill" : "pause.fill",
                label: session.isPaused ? tr("继续") : tr("暂停"),
                filled: false,
                action: onTogglePause
            )
            iconButton(systemName: "stop.fill", label: tr("停止"), filled: true, action: onStop)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
    }

    private func iconButton(systemName: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? AppColor.onAccent : ink)
                .frame(width: 22, height: 22)
                .background(filled ? AppColor.accent : AppColor.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
