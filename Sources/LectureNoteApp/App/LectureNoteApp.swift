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
            .frame(minWidth: 960, minHeight: 640)
            .modifier(ReduceMotionBridge())
            .modifier(ForcedColorScheme(scheme: forcedScheme))
    }

    private func applyPreview(_ name: String?) {
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
