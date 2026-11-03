import Foundation
import Testing
@testable import LectureNoteApp

struct TranscriptionTopicTests {
    @Test func recurringCourseWordsComeFirstAndEverydayWordsAreLeftOut() {
        let slides = """
        Community detection with the Louvain method. Louvain maximizes modularity.
        Modularity compares edges inside communities with a random graph. This slide shows an example.
        Betweenness centrality: BFS from every node. BFS again for weighted edges.
        """
        let terms = TranscriptionTopic.terms(in: slides)
        #expect(terms.prefix(4).contains("Louvain"))
        #expect(terms.contains { $0.lowercased() == "modularity" })
        #expect(terms.contains("BFS"), "acronyms keep their capitals")
        #expect(!terms.contains { ["this", "slide", "example", "with"].contains($0.lowercased()) })
        #expect(!terms.contains("centrality"), "a word seen once is not a recurring term")
    }

    @Test func chineseTermsAreFoundWithoutFunctionWords() {
        let slides = "图的节点和边。节点的度数。节点越多，边越多。社区发现算法把节点分组。社区发现很重要，社区发现常用模块度。"
        let terms = TranscriptionTopic.terms(in: slides)
        #expect(terms.contains("节点"))
        #expect(terms.contains("社区发现"))
        #expect(!terms.contains { $0.contains("的") })
        #expect(!terms.contains("社区"), "a shorter piece of an equally common term is dropped")
    }

    @Test func theHintNamesTheLectureAndSkipsTheDefaultTitle() {
        #expect(TranscriptionTopic.text(title: "Graph Visualization", course: "CS 5040", terms: ["node", "edge"])
            == "Lecture: Graph Visualization. Course: CS 5040. Terms: node, edge.")
        #expect(TranscriptionTopic.text(title: tr("未命名会议"), course: nil, terms: []).isEmpty)
    }
}
