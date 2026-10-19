import AppKit
import SwiftUI

struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion

    private var compact: Bool { model.meetingCompact && model.openMeetingID != nil }

    var body: some View {
        ZStack {
            if compact, let meetingID = model.openMeetingID {
                CompactMeetingView(model: model, meetingID: meetingID, reduceMotion: reduce)
                    .transition(.opacity)
            } else {
                browser
                    .transition(.opacity)
            }
        }
        .animation(MeetingWindowFrame.animation(reduceMotion: reduce), value: compact)
        .background(AppColor.canvas.ignoresSafeArea())
        .background {
            MeetingWindowFrame(
                compact: compact,
                reduceMotion: reduce,
                allowsCompactFrame: $model.windowAllowsCompact
            )
        }
        .overlay {
            if let image = model.enlargedImage {
                ChatImageLightbox(image: image, name: model.enlargedImageName, fileURL: model.enlargedImageURL, reduceMotion: reduce) {
                    model.enlargedImage = nil
                    model.enlargedImageURL = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nomiEnlargeImage)) { note in
            guard let image = note.userInfo?["image"] as? NSImage else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.enlargedImage = image
                model.enlargedImageName = (note.userInfo?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "image.png"
                model.enlargedImageURL = note.userInfo?["url"] as? URL
            }
        }
        .containerBackground(AppColor.canvas, for: .window)
        .sheet(isPresented: $model.recordingSetupPresented) {
            RecordingSetupView(model: model)
        }
        .alert(tr("导出失败"), isPresented: exportFailed) {
            Button(tr("好"), role: .cancel) {}
        } message: {
            Text(model.exportError ?? "")
        }
        .alert(tr("会议存储"), isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button(tr("好"), role: .cancel) {}
        } message: {
            Text(model.storageError ?? "")
        }
    }

    private var exportFailed: Binding<Bool> {
        Binding(
            get: { model.exportError != nil },
            set: { if !$0 { model.exportError = nil } }
        )
    }

    private var reduce: Bool { reduceMotion }

    private var browser: some View {
        VStack(spacing: 0) {
            TopBar(model: model, reduceMotion: reduce)
            HStack(spacing: 0) {
                Rail(model: model, reduceMotion: reduce)
                page
                    .id(model.page)
                    .transition(.pageEnter(reduceMotion: reduce))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .meetings:
            MeetingsPage(model: model, reduceMotion: reduce)
        case .ask:
            AskView(model: model)
        case .sources:
            SourcesView(model: model)
        case .help:
            HelpView()
        case .settings:
            SettingsView(model: model)
        }
    }
}
