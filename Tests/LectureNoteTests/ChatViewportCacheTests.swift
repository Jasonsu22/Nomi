import AppKit
import Foundation
import Testing
@testable import LectureNoteApp

@Suite(.serialized)
struct ChatViewportCacheTests {
    @Test @MainActor func reusesMatchingWidthAndKeepsAnchorAcrossResize() {
        let cache = ChatViewportCache()
        let session = UUID()
        let row = UUID()
        cache.store(.init(heights: [row: 240], anchorID: row, anchorOffset: 18, followsLatest: false, width: 680), for: session)

        let same = try! #require(cache.snapshot(for: session, width: 680))
        #expect(same.heights[row] == 240)
        #expect(same.anchorID == row)
        #expect(same.anchorOffset == 18)

        let resized = try! #require(cache.snapshot(for: session, width: 720))
        #expect(resized.heights.isEmpty)
        #expect(resized.anchorID == row)
        #expect(resized.anchorOffset == 18)
    }

    @Test @MainActor func evictsLeastRecentlyUsedConversation() {
        let cache = ChatViewportCache()
        let ids = (0..<5).map { _ in UUID() }
        for id in ids {
            cache.store(.init(heights: [:], anchorID: nil, anchorOffset: 0, followsLatest: true, width: 600), for: id)
        }
        #expect(cache.snapshot(for: ids[0], width: 600) == nil)
        #expect(cache.snapshot(for: ids[4], width: 600) != nil)
    }
}
