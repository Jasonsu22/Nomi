import Foundation
import Testing
@testable import LectureNoteApp

struct HelpMailTests {
    @Test func contactUsOpensAPrefilledEmail() throws {
        let url = try #require(HelpView.mailURL())
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "jasonsu210@gmail.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"]?.contains("Nomi") == true)
        let body = try #require(items["body"])
        #expect(body.contains("macOS"))
        #expect(body.contains("Nomi "))
        // Line breaks survive the round trip, so the template keeps its layout.
        #expect(body.split(separator: "\n").count > 5)
    }
}
