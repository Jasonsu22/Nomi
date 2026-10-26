import AppKit
import SwiftUI

struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var visitedPages: Set<AppPage> = []

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
        .background(RecordingWindowLevel(recording: model.engine.session.phase != .idle))
        .overlay(alignment: .bottomTrailing) {
            if let popup = model.questionPopup, model.engine.session.phase != .idle {
                QuestionPopupView(model: model, popup: popup, reduceMotion: reduce)
                    .id(popup.id)
                    .padding(24)
                    .transition(reduce ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
            }
        }
        .animation(reduce ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.82), value: model.questionPopup?.id)
        .overlay {
            if let image = model.enlargedImage {
                ChatImageLightbox(image: image, name: model.enlargedImageName, fileURL: model.enlargedImageURL, reduceMotion: reduce) {
                    model.enlargedImage = nil
                    model.enlargedImageURL = nil
                }
            }
        }
        .sheet(isPresented: $model.onboardingPresented) {
            OnboardingView(model: model)
                .interactiveDismissDisabled()
        }
        .onAppear {
            // First launch only; afterwards the top bar and Help reopen it.
            if !OnboardingPreference.done, model.engine is LocalEngine { model.onboardingPresented = true }
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
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(TutorialAnchors.self) { anchors in
            if let stop = model.tutorialStep {
                TutorialOverlay(model: model, stop: stop, anchors: anchors, reduceMotion: reduce)
            }
        }
    }

    /// The primary pages stay built after their first visit, so returning to one
    /// only fades it in instead of rebuilding every meeting row and chat answer.
    /// Help and Settings are cheap and keep the original rebuild on each visit.
    private var pages: some View {
        ZStack {
            ForEach(AppPage.keptAlive) { page in
                if visitedPages.contains(page) || model.page == page {
                    self.page(page)
                        .keptPage(active: model.page == page, reduceMotion: reduce)
                        .transition(.pageEnter(reduceMotion: reduce))
                }
            }
            if !AppPage.keptAlive.contains(model.page) {
                page(model.page)
                    .id(model.page)
                    .transition(.pageEnter(reduceMotion: reduce))
                    .zIndex(2)
            }
        }
        .onChange(of: model.page, initial: true) { _, page in
            // A hidden page must not keep keyboard focus, as the rebuilt page used to drop it.
            NSApp.keyWindow?.makeFirstResponder(nil)
            if AppPage.keptAlive.contains(page) { visitedPages.insert(page) }
        }
    }

    @ViewBuilder
    private func page(_ page: AppPage) -> some View {
        switch page {
        case .meetings:
            MeetingsPage(model: model, reduceMotion: reduce)
        case .ask:
            AskView(model: model)
        case .sources:
            SourcesView(model: model)
        case .help:
            HelpView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}
