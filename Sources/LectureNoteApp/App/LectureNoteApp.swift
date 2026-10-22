import AppKit
import SwiftUI

@main
struct LectureNoteApp: App {
    @State private var model = AppModel()
    @AppStorage(InterfaceLanguage.key) private var interfaceLanguage = InterfaceLanguage.system.rawValue
    @AppStorage(InterfaceAppearance.key) private var appearance = InterfaceAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            root
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.shutdown()
                }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let image = NSImage(contentsOf: url) {
                        NSApplication.shared.applicationIconImage = image
                    }
                    NSApplication.shared.activate()
                    #if DEBUG
                    applyPreview(ProcessInfo.processInfo.environment["LECTURE_PREVIEW"])
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("开始转录")) {
                    model.prepareRecording()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.canStart)

                Button(tr("停止转录")) {
                    model.stopTranscription()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.engine.session.phase == .idle || model.engine.session.phase == .stopping)

                Button(tr("新会话")) {
                    model.beginNewChat()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.page != .ask)
            }
            CommandGroup(after: .sidebar) {
                Button(tr("搜索会议")) {
                    model.requestSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    private var root: some View {
        AppShell(model: model)
            .id(interfaceLanguage)
            .environment(\.locale, InterfaceLanguage.resolved(interfaceLanguage).locale)
            .frame(
                minWidth: model.windowAllowsCompact ? 360 : 960,
                minHeight: model.windowAllowsCompact ? 560 : 640
            )
            .modifier(ReduceMotionBridge())
            .modifier(ForcedColorScheme(scheme: forcedScheme))
    }

    private func applyPreview(_ name: String?) {
        // Debug-only screenshots: LECTURE_PAGE picks a page (settings:search or settings:memory scrolls),
        // LECTURE_WINDOW sets the window to WIDTHxHEIGHT or "full" for full screen.
        let environment = ProcessInfo.processInfo.environment
        if let page = environment["LECTURE_PAGE"] {
            let parts = page.split(separator: ":").map(String.init)
            if let target = AppPage(rawValue: parts[0]) { model.page = target }
            if parts.count > 1 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if parts[1] == "search" { model.revealSearchSettings = true }
                    if parts[1] == "memory" { model.revealMemorySettings = true }
                }
            }
        }
        if let size = environment["LECTURE_WINDOW"] {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
                if size == "full" {
                    window.toggleFullScreen(nil)
                } else {
                    let parts = size.split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 { window.setFrame(NSRect(x: 40, y: 40, width: parts[0], height: parts[1]), display: true) }
                }
            }
        }
        switch name {
        case "detail":
            if let meeting = model.meetings.first(where: { !$0.isLive }) {
                model.openMeeting(meeting.id)
            }
        case "english":
            if let meeting = model.meetings.first(where: { $0.sourceLanguage == "en" }) {
                model.openMeeting(meeting.id)
            }
        case "live":
            model.startTranscription()
        default:
            break
        }
    }

    private var forcedScheme: ColorScheme? {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["LECTURE_COLOR_SCHEME"] {
            if value == "dark" { return .dark }
            if value == "light" { return .light }
        }
        #endif
        return (InterfaceAppearance(rawValue: appearance) ?? .system).colorScheme
    }
}

private struct ForcedColorScheme: ViewModifier {
    var scheme: ColorScheme?

    func body(content: Content) -> some View {
        content.preferredColorScheme(scheme)
    }
}
