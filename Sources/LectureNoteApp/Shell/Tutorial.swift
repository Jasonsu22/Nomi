import SwiftUI

/// The quick tutorial: one short tip for each main button, in this order.
enum TutorialStop: Int, CaseIterable, Hashable {
    case meetings
    case record
    case sources
    case chat
    case settings

    var title: String {
        switch self {
        case .meetings: tr("会议")
        case .record: tr("开始转录")
        case .sources: tr("资料")
        case .chat: tr("提问")
        case .settings: tr("设置")
        }
    }

    var body: String {
        switch self {
        case .meetings: tr("录过的会议和转写都在这里。打开一场会议可以看原文、译文和摘要。")
        case .record: tr("点这里选择输入设备和语言，然后开始录音。识别和翻译都在这台 Mac 上进行。")
        case .sources: tr("导入课件和文档，提问时可以让 Nomi 参考它们。")
        case .chat: tr("针对会议和资料提问。打开「联网」后，Nomi 也会上网查资料。")
        case .settings: tr("在这里选择模型、填写 API 和搜索密钥。")
        }
    }
}

struct TutorialAnchors: PreferenceKey {
    static let defaultValue: [TutorialStop: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TutorialStop: Anchor<CGRect>], nextValue: () -> [TutorialStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks the control the tutorial points at for `stop`.
    func tutorialTarget(_ stop: TutorialStop) -> some View {
        anchorPreference(key: TutorialAnchors.self, value: .bounds) { [stop: $0] }
    }
}

/// Dims the window, leaves the current button visible, and shows its tip beside it.
struct TutorialOverlay: View {
    var model: AppModel
    var stop: TutorialStop
    var anchors: [TutorialStop: Anchor<CGRect>]
    var reduceMotion: Bool

    private let bubbleWidth: CGFloat = 300

    var body: some View {
        GeometryReader { proxy in
            let target = anchors[stop].map { proxy[$0].insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                dim(size: proxy.size, hole: target)
                bubble
                    .frame(width: bubbleWidth, alignment: .leading)
                    .offset(bubbleOffset(target: target, size: proxy.size))
            }
            .animation(Motion.layout(reduceMotion), value: stop)
        }
        .transition(.opacity)
    }

    private func dim(size: CGSize, hole: CGRect?) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole {
                path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
            }
        }
        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
        // Clicks during the tutorial go to its buttons only.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(trf("第 %d 步，共 %d 步", stop.rawValue + 1, TutorialStop.allCases.count))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(stop.title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text(stop.body)
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Button(tr("跳过")) { finish() }
                    .buttonStyle(.plain.clicking())
                    .foregroundStyle(AppColor.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if stop.rawValue > 0 {
                    Button(tr("上一步")) { move(by: -1) }
                        .clickCursor()
                }
                Button(isLast ? tr("完成") : tr("下一步")) {
                    if isLast { finish() } else { move(by: 1) }
                }
                .buttonStyle(.borderedProminent.clicking())
                .keyboardShortcut(.defaultAction)
            }
            .font(AppFont.secondary)
            .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var isLast: Bool { stop == TutorialStop.allCases.last }

    private func move(by step: Int) {
        guard let next = TutorialStop(rawValue: stop.rawValue + step) else { return }
        model.tutorialStep = next
    }

    private func finish() {
        withAnimation(Motion.fade(reduceMotion)) { model.tutorialStep = nil }
    }

    /// Beside a rail button, below a top-bar button, and centered when the button is not on screen.
    private func bubbleOffset(target: CGRect?, size: CGSize) -> CGSize {
        let estimatedHeight: CGFloat = 190
        guard let target else {
            return CGSize(width: (size.width - bubbleWidth) / 2, height: (size.height - estimatedHeight) / 2)
        }
        let x: CGFloat
        let y: CGFloat
        if target.midX < size.width / 3 {
            x = target.maxX + Space.s3
            y = target.minY
        } else {
            x = target.maxX - bubbleWidth
            y = target.maxY + Space.s3
        }
        return CGSize(
            width: min(max(Space.s3, x), size.width - bubbleWidth - Space.s3),
            height: min(max(Space.s3, y), size.height - estimatedHeight - Space.s3)
        )
    }
}
