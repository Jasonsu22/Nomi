import Foundation
import Testing
@testable import LectureNoteApp

@MainActor
struct TitleBarDoubleClickTests {
    @Test func followsTheSystemSetting() {
        #expect(TitleBarDoubleClick.action(setting: nil, minimizes: false) == .zoom, "fills the screen when nothing is set")
        #expect(TitleBarDoubleClick.action(setting: "Minimize", minimizes: false) == .minimize)
        #expect(TitleBarDoubleClick.action(setting: "None", minimizes: false) == .nothing)
        #expect(TitleBarDoubleClick.action(setting: "Fill", minimizes: false) == .zoom)
        #expect(TitleBarDoubleClick.action(setting: nil, minimizes: true) == .minimize, "the older setting still counts")
    }
}
