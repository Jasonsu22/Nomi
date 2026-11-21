import SwiftUI

/// Settings › Live speakers: tell speakers apart while recording, and which model does it. Each
/// model is a separate download, kept in Application Support/FluidAudio; none ship with Nomi.
struct SpeakerModelsSection: View {
    @AppStorage(SpeakerModelKind.enabledKey) private var enabled = true
    @AppStorage(SpeakerModelKind.choiceKey) private var chosen = SpeakerModelKind.standard.rawValue
    @State private var downloading: Set<SpeakerModelKind> = []
    @State private var failed: [SpeakerModelKind: String] = [:]
    /// Bumped after a download or removal, so the rows read the disk again.
    @State private var refresh = 0

    var body: some View {
        SettingsSection(tr("实时区分说话人（实验）")) {
            SettingsRow(tr("录音时标出说话人"), detail: tr("在这台 Mac 上边录边分出老师、你和其他人，转写里每段话前会标出是谁说的。下一次开始录音时生效。")) {
                SettingsSwitch(label: tr("录音时标出说话人"), isOn: $enabled)
            }
            ForEach(SpeakerModelKind.allCases) { kind in
                row(kind)
            }
        } footer: {
            Text(tr("三个模型都在两节真实课堂录音上测过，和录音结束后的分析结果一致率在 92%–100%。模型只在用到时下载，可以随时删除。"))
        }
        .id(refresh)
    }

    private func row(_ kind: SpeakerModelKind) -> some View {
        let downloaded = kind.isDownloaded
        let isChosen = chosen == kind.rawValue
        return SettingsRow(kind.title + (isChosen ? " · " + tr("使用中") : ""), detail: failed[kind] ?? "\(kind.detail) \(kind.size)") {
            HStack(spacing: Space.s2) {
                if downloading.contains(kind) {
                    ProgressView().controlSize(.small)
                    Text(tr("正在下载…")).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                } else if downloaded {
                    if !isChosen {
                        Button(tr("使用")) { chosen = kind.rawValue }
                            .buttonStyle(.bordered.clicking())
                    }
                    Button(tr("删除")) {
                        kind.remove()
                        if isChosen { chosen = SpeakerModelKind.standard.rawValue }
                        refresh += 1
                    }
                    .buttonStyle(.plain.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                } else {
                    Button(trf("下载 %@", kind.size)) { download(kind) }
                        .buttonStyle(.bordered.clicking())
                }
            }
            .font(AppFont.secondary)
        }
    }

    private func download(_ kind: SpeakerModelKind) {
        downloading.insert(kind)
        failed[kind] = nil
        Task {
            do {
                _ = try await kind.load()
                chosen = kind.rawValue
            } catch {
                failed[kind] = trf("下载失败：%@", error.localizedDescription)
            }
            downloading.remove(kind)
            refresh += 1
        }
    }
}
