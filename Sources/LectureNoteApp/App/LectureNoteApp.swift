import AppKit
import SwiftUI

@main
struct LectureNoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            root
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                    applyPreview(ProcessInfo.processInfo.environment["LECTURE_PREVIEW"])
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("开始转录") {
                    model.startTranscription()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.engine.session.phase != .idle)

                Button("停止转录") {
                    model.stopTranscription()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.engine.session.phase == .idle || model.engine.session.phase == .stopping)
            }
            CommandGroup(after: .sidebar) {
                Button("搜索会议") {
                    model.requestSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    private var root: some View {
        AppShell(model: model)
            .frame(minWidth: 960, minHeight: 640)
            .environment(\.appReduceMotion, ReduceMotion.system)
            .modifier(ForcedColorScheme(scheme: forcedScheme))
    }

    private func applyPreview(_ name: String?) {
        switch name {
        case "detail":
            if let meeting = model.meetings.first(where: { !$0.isLive }) {
                model.openMeeting(meeting.id)
            }
        case "live":
            model.startTranscription()
        default:
            break
        }
    }

    private var forcedScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["LECTURE_COLOR_SCHEME"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

private struct ForcedColorScheme: ViewModifier {
    var scheme: ColorScheme?

    func body(content: Content) -> some View {
        if let scheme {
            content.preferredColorScheme(scheme)
        } else {
            content
        }
    }
}
