import SwiftUI

struct SessionControl: View {
    var session: SessionState
    var meter: LevelMeter
    var reduceMotion: Bool
    var onStart: () -> Void
    var onStop: () -> Void
    var onTogglePause: () -> Void
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            control
                .background(prominent ? AppColor.accent : AppColor.surface, in: Capsule())
                .overlay {
                    if !prominent {
                        Capsule().strokeBorder(AppColor.separator, lineWidth: 1)
                    }
                }
                .glassEffect(glass, in: Capsule())
                .glassEffectID("session", in: glassNamespace)
        }
    }

    private var prominent: Bool {
        session.phase == .idle || session.phase == .preparing
    }

    private var glass: Glass {
        prominent ? .clear.interactive(session.phase == .idle) : .regular
    }

    private var ink: Color {
        switch session.phase {
        case .idle, .preparing: AppColor.onAccent
        case .listening, .stopping: AppColor.textPrimary
        }
    }

    @ViewBuilder
    private var control: some View {
        switch session.phase {
        case .idle:
            Button(action: onStart) {
                label(title: "开始转录", pulsing: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始转录")
        case .preparing:
            label(title: "准备中", pulsing: true)
                .accessibilityLabel("准备中")
        case .listening:
            listening
        case .stopping:
            Text("正在保存")
                .font(AppFont.secondary.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
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
        .frame(height: 36)
    }

    private var listening: some View {
        HStack(spacing: 10) {
            WaveformIcon(meter: meter)
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
                label: session.isPaused ? "继续" : "暂停",
                filled: false,
                action: onTogglePause
            )
            iconButton(systemName: "stop.fill", label: "停止", filled: true, action: onStop)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 36)
    }

    private func iconButton(systemName: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? Color.white : AppColor.textPrimary)
                .frame(width: 22, height: 22)
                .background(filled ? AppColor.accent : AppColor.surfaceMuted, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct WaveformIcon: View {
    var meter: LevelMeter

    var body: some View {
        Image(systemName: "waveform", variableValue: min(1, max(0, meter.rms)))
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 18)
    }
}
