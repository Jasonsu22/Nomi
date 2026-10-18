import Testing
@testable import LectureNoteApp

struct LanguagePreferenceTests {
    @Test func preferredLanguageMapsOntoASupportedSource() {
        #expect(LectureLanguages.code(forPreferred: "zh-Hans-CN") == "zh")
        #expect(LectureLanguages.code(forPreferred: "en-US") == "en")
        #expect(LectureLanguages.code(forPreferred: "ja-JP") == "ja")
        #expect(LectureLanguages.code(forPreferred: "pt-BR") == "en")
    }

    @Test func targetPairsChineseAndEnglishUnlessTheUserChooses() {
        let chinese = LectureLanguages.resolve(preferred: "zh-Hans", storedSource: nil, storedTarget: nil)
        #expect(chinese.source == "zh")
        #expect(chinese.target == "en")

        let english = LectureLanguages.resolve(preferred: "en-US", storedSource: "system", storedTarget: nil)
        #expect(english.source == "en")
        #expect(english.target == "zh")

        let chosen = LectureLanguages.resolve(preferred: "en-US", storedSource: "zh", storedTarget: "ja")
        #expect(chosen.source == "zh")
        #expect(chosen.target == "ja")

        let off = LectureLanguages.resolve(preferred: "zh-CN", storedSource: nil, storedTarget: "none")
        #expect(off.target == "none")
    }
}
