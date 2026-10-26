import AVFoundation
import SwiftUI

/// The first-start guide: welcome, download the speech and translation models, allow the
/// microphone, then start. Downloads keep going after the guide closes.
struct OnboardingView: View {
    var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var asrChoice: LocalModelDefinition?
    @State private var translatorChoice: LocalModelDefinition?
    @State private var started = false
    @State private var microphone = AVAudioApplication.shared.recordPermission

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? AppColor.accent : AppColor.separator)
                        .frame(width: index == step ? 22 : 7, height: 7)
                }
            }
            .animation(Motion.layout(reduceMotion), value: step)
            .padding(.bottom, Space.s5)
            Group {
                switch step {
                case 0: welcome
                case 1: models
                case 2: microphoneStep
                default: ready
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
        .padding(.bottom, 26)
        .frame(width: 600)
        .background(AppColor.surface)
        .onAppear {
            asrChoice = asrChoice ?? model.recommendedModel(for: .asr)
            translatorChoice = translatorChoice ?? model.recommendedModel(for: .translator)
            model.localModels.refresh()
            // Reopened because the speech model is missing: go straight to the downloads.
            if OnboardingPreference.done { step = 1 }
        }
    }

    private func go(_ next: Int) {
        withAnimation(Motion.page(reduceMotion)) { step = max(0, min(steps - 1, next)) }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLogo(side: 64)
            Text(tr("欢迎使用 Nomi"))
                .font(.system(size: 26, weight: .bold))
                .padding(.top, Space.s3)
            Text(tr("用母语听懂每一节课。"))
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 4)
                .padding(.bottom, Space.s4)
            feature("waveform", tr("实时转写"), tr("老师说话时，文字随之出现。"))
            feature("character.bubble", tr("每一句下面都有翻译"), tr("支持中文、英文等九种语言。"))
            feature("bubble.left.and.text.bubble.right", tr("针对任何一节课提问"), tr("提问、摘要，还会回答老师在课上提的问题。"))
            footer {
                Button(tr("稍后设置")) { model.finishOnboarding(startTour: false) }
                    .buttonStyle(.link.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Button(tr("开始")) { go(1) }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var models: some View {
        let asr = asrChoice ?? model.recommendedModel(for: .asr)
        let translator = translatorChoice ?? model.recommendedModel(for: .translator)
        let items = [asr, translator]
        let allInstalled = items.allSatisfy { model.localModels.installed.contains($0.id) }
        let downloading = items.contains { model.localModels.downloads[$0.id] != nil }
        let missingBytes = items.filter { !model.localModels.installed.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            Text(tr("下载模型")).font(.system(size: 22, weight: .bold))
            Text(tr("Nomi 在这台 Mac 上听写和翻译。两个模型只需下载一次，之后可以离线使用。"))
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, Space.s4)
            modelCard(tr("语音识别"), detail: tr("把讲课变成文字"), role: .asr, item: asr, choice: $asrChoice, locked: started)
            modelCard(tr("翻译"), detail: tr("翻译每一段，也能离线回答问题"), role: .translator, item: translator, choice: $translatorChoice, locked: started)
            Label(tr("录音不会离开这台 Mac。模型保存在 ~/.OminiX/models。"), systemImage: "lock")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, Space.s2)
            footer {
                Button(tr("返回")) { go(0) }
                    .buttonStyle(.link.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                if allInstalled {
                    Button(tr("下一步")) {
                        // Already downloaded: make sure these are the models in use.
                        if !started {
                            started = true
                            model.downloadAndUse(asr, for: .asr)
                            model.downloadAndUse(translator, for: .translator)
                        }
                        go(2)
                    }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
                } else if started || downloading {
                    Button(tr("下载时继续")) { go(2) }
                        .buttonStyle(.bordered.clicking())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(trf("下载两个模型 · %@", ByteCountFormatter.string(fromByteCount: missingBytes, countStyle: .file))) {
                        started = true
                        model.downloadAndUse(asr, for: .asr)
                        model.downloadAndUse(translator, for: .translator)
                    }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("允许使用麦克风")).font(.system(size: 22, weight: .bold))
            Text(tr("Nomi 需要麦克风才能听到课堂。声音只在这台 Mac 上处理。"))
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, Space.s4)
            HStack(spacing: Space.s4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 54, height: 54)
                    .background(AppColor.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("麦克风")).font(AppFont.body.weight(.semibold))
                    Text(tr("macOS 只会问一次。")).font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Text(microphoneLabel)
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(microphone == .granted ? AppColor.accentGreen : (microphone == .denied ? Color.red : AppColor.textSecondary))
            }
            .padding(Space.s4)
            .background(AppColor.surfaceInset.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            footer {
                Button(tr("返回")) { go(1) }
                    .buttonStyle(.link.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                if microphone == .granted {
                    Button(tr("下一步")) { go(3) }
                        .buttonStyle(.borderedProminent.clicking())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("跳过")) { go(3) }
                        .buttonStyle(.bordered.clicking())
                    Button(microphone == .denied ? tr("打开系统设置") : tr("允许使用麦克风")) { askMicrophone() }
                        .buttonStyle(.borderedProminent.clicking())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var ready: some View {
        let asr = asrChoice ?? model.recommendedModel(for: .asr)
        let progress = model.localModels.downloads[asr.id]
        let waiting = !model.localModels.installed.contains(asr.id)
        return VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColor.accentGreen)
                .frame(width: 64, height: 64)
                .background(AppColor.accentGreen.opacity(0.14), in: Circle())
            Text(tr("准备好了")).font(.system(size: 22, weight: .bold)).padding(.top, Space.s3)
            Text(tr("上课时点右上角的「开始转录」，在那里选择课堂语言和翻译语言。"))
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if waiting {
                HStack(spacing: Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(progress.map { trf("正在下载语音识别模型 · %d%%", Int($0.fraction * 100)) } ?? tr("语音识别模型还没下载。"))
                        .font(AppFont.secondary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppColor.accent)
                .padding(Space.s3)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, Space.s4)
                Text(tr("模型下载好后就能开始录音，在这之前可以先看看 Nomi。"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 6)
            }
            footer {
                Button(tr("返回")) { go(2) }
                    .buttonStyle(.link.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Button(tr("快速导览")) { model.finishOnboarding(startTour: true) }
                    .buttonStyle(.bordered.clicking())
                Button(tr("开始使用 Nomi")) { model.finishOnboarding(startTour: false) }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.accent)
                .frame(width: 36, height: 36)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body.weight(.semibold))
                Text(detail).font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, 7)
    }

    private func modelCard(_ title: String, detail: String, role: LocalModelRole, item: LocalModelDefinition,
                           choice: Binding<LocalModelDefinition?>, locked: Bool) -> some View {
        let installed = model.localModels.installed.contains(item.id)
        let progress = model.localModels.downloads[item.id]
        let error = model.localModels.errors[item.id]
        let recommended = item.id == model.recommendedModel(for: role).id
        let alternative = model.alternativeModel(for: role)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.s2) {
                Text(title).font(AppFont.body.weight(.semibold))
                if recommended {
                    Text(tr("推荐这台 Mac 使用"))
                        .font(AppFont.caption.weight(.bold))
                        .foregroundStyle(AppColor.accentGreen)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(AppColor.accentGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Spacer()
                Text(installed ? tr("已下载 ✓") : progress.map { "\(Int($0.fraction * 100))%" } ?? item.sizeLabel)
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(installed ? AppColor.accentGreen : AppColor.textSecondary)
                    .monospacedDigit()
            }
            Text("\(item.name) · \(detail)").font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
            if let progress {
                ProgressView(value: progress.fraction).tint(AppColor.accentGreen).padding(.top, 4)
            }
            if let error {
                HStack {
                    Text(error).font(AppFont.caption).foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button(tr("重试")) { model.downloadAndUse(item, for: role) }.controlSize(.small)
                }
            } else if !locked, !installed, progress == nil, let alternative {
                Button(alternative.id == model.recommendedModel(for: role).id
                       ? trf("改用推荐的 %@", alternative.name)
                       : trf("改用更轻的 %@（%@）", alternative.name, alternative.sizeLabel)) {
                    choice.wrappedValue = alternative
                }
                .buttonStyle(.link.clicking())
                .font(AppFont.caption)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppColor.separator))
        .padding(.bottom, Space.s2)
    }

    private func footer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Space.s2) { content() }
            .padding(.top, Space.s5)
    }

    private var microphoneLabel: String {
        switch microphone {
        case .granted: tr("已允许 ✓")
        case .denied: tr("已拒绝")
        default: tr("还没允许")
        }
    }

    private func askMicrophone() {
        if microphone == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        Task {
            _ = await Self.requestRecordPermission()
            microphone = AVAudioApplication.shared.recordPermission
        }
    }

    /// The completion runs on an arbitrary thread, so the continuation is formed off the main actor.
    private nonisolated static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
