import AppKit
import Foundation
import Testing
@testable import LectureNoteApp

/// Each file type Nomi reads, from small sample files written here.
struct FileReadingTests {
    private let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-reading-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func text(_ url: URL) -> String {
        SourceText.blocks(url: url, title: url.lastPathComponent, sourceID: UUID()).map(\.body).joined(separator: "\n")
    }

    /// Writes `files` (path → contents) into a folder and zips it the way Office and e-book files are.
    private func zipped(_ name: String, _ files: [String: String], binary: [String: Data] = [:]) throws -> URL {
        let source = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for (path, contents) in files.mapValues({ Data($0.utf8) }).merging(binary, uniquingKeysWith: { $1 }) {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url)
        }
        let archive = folder.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", source.path, archive.path]
        try process.run()
        process.waitUntilExit()
        return archive
    }

    @Test func plainTextInAnyCommonEncoding() throws {
        #expect(text(try file("notes.md", Data("# Week 3\nMitosis".utf8))).contains("Mitosis"))
        #expect(text(try file("grades.csv", Data("name,score\nAda,92".utf8))).contains("Ada,92"))
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let chinese = try #require("细胞分裂的过程".data(using: gb18030))
        #expect(text(try file("old.txt", chinese)) == "细胞分裂的过程", "older Chinese files are often GB18030")
    }

    @Test func webPagesKeepTheirTextAndDropScripts() throws {
        let html = "<html><head><title>x</title><style>p{}</style></head><body><h1>Osmosis</h1><p>Water moves &amp; more</p><script>alert(1)</script></body></html>"
        let read = text(try file("page.html", Data(html.utf8)))
        #expect(read.contains("Osmosis"))
        #expect(read.contains("Water moves & more"))
        #expect(!read.contains("alert"))
        let archive = try PropertyListSerialization.data(
            fromPropertyList: ["WebMainResource": ["WebResourceData": Data("<p>Saved page</p>".utf8)]], format: .binary, options: 0)
        #expect(text(try file("saved.webarchive", archive)) == "Saved page")
    }

    @Test func wordRichTextAndOpenDocument() throws {
        let content = NSAttributedString(string: "Photosynthesis makes glucose.")
        for (name, type) in [("a.docx", NSAttributedString.DocumentType.officeOpenXML), ("b.rtf", .rtf), ("c.odt", .openDocument)] {
            let data = try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: type])
            #expect(text(try file(name, data)).contains("Photosynthesis"), "\(name)")
        }
    }

    /// Word files full of screenshots: the text in each picture is read too.
    @Test func picturesInsideAWordFileAreRead() throws {
        let image = NSImage(size: NSSize(width: 900, height: 200), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            ("Mitochondria make energy" as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 56)])
            return true
        }
        let png = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        // Laid out the way Word saves a picture: the document points at it through its relationships.
        let docx = try zipped("shots.docx", [
            "[Content_Types].xml": #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"#,
            "_rels/.rels": #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#,
            "word/document.xml": #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body><w:p><w:r><w:t>Screenshot below</w:t></w:r></w:p><w:p><w:r><w:drawing><a:blip r:embed="rId7"/></w:drawing></w:r></w:p></w:body></w:document>"#,
            "word/_rels/document.xml.rels": #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>"#,
        ], binary: ["word/media/image1.png": png])
        let blocks = SourceText.blocks(url: docx, title: "shots.docx", sourceID: UUID())
        #expect(blocks.contains { $0.body.localizedCaseInsensitiveContains("Mitochondria") })
    }

    @Test func spreadsheetsReadEachSheetsRows() throws {
        let book = try zipped("marks.xlsx", [
            "xl/workbook.xml": #"<workbook><sheets><sheet name="Midterm" sheetId="1"/></sheets></workbook>"#,
            "xl/sharedStrings.xml": "<sst><si><t>Name</t></si><si><t>Ada</t></si></sst>",
            "xl/worksheets/sheet1.xml": #"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>Score</t></is></c></row><row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>92</v></c></row></sheetData></worksheet>"#,
        ])
        let blocks = SourceText.blocks(url: book, title: "marks.xlsx", sourceID: UUID())
        #expect(blocks.first?.detail == "Midterm")
        #expect(blocks.first?.body == "Name | Score\nAda | 92")
    }

    @Test func slidesIncludeTheirSpeakerNotes() throws {
        let deck = try zipped("talk.pptx", [
            "ppt/slides/slide1.xml": "<p:sld><a:t>Cell cycle</a:t></p:sld>",
            "ppt/slides/slide2.xml": "<p:sld><a:t>Mitosis</a:t></p:sld>",
            "ppt/notesSlides/notesSlide2.xml": "<p:notes><a:t>Ask about prophase</a:t></p:notes>",
        ])
        let blocks = SourceText.blocks(url: deck, title: "talk.pptx", sourceID: UUID())
        #expect(blocks.count == 2)
        #expect(blocks[1].body.contains("Mitosis") && blocks[1].body.contains("Ask about prophase"))
    }

    @Test func eBooksReadChaptersInOrder() throws {
        let book = try zipped("book.epub", [
            "META-INF/container.xml": #"<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"#,
            "OEBPS/content.opf": #"<package><manifest><item id="b" href="two.xhtml"/><item id="a" href="one.xhtml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>"#,
            "OEBPS/one.xhtml": "<html><body><p>First chapter</p></body></html>",
            "OEBPS/two.xhtml": "<html><body><p>Second chapter</p></body></html>",
        ])
        let blocks = SourceText.blocks(url: book, title: "book.epub", sourceID: UUID())
        #expect(blocks.map(\.body) == ["First chapter", "Second chapter"])
    }

    @Test func longTextBecomesPartsAQuestionCanChooseFrom() {
        let paragraph = String(repeating: "word ", count: 300)
        let parts = SourceText.passages(Array(repeating: paragraph, count: 20).joined(separator: "\n"))
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= SourceText.passageLength })
    }

    @Test func unreadableTypesAreTurnedAwayWithAReason() {
        #expect(!SourceText.canRead(URL(fileURLWithPath: "/tmp/deck.key")))
        #expect(SourceText.refusal(for: URL(fileURLWithPath: "/tmp/deck.key")).contains("key"))
        #expect(!SourceText.canRead(URL(fileURLWithPath: "/tmp/archive.zip")))
        #expect(SourceStore.accepts(URL(fileURLWithPath: "/tmp/sheet.xlsx")), "the Sources page takes the same list")
    }

    /// Finder puts each file's icon on the pasteboard beside the file; the file is what gets attached.
    @Test func aFileCopiedInFinderIsAttachedNotItsIcon() throws {
        let document = try file("Essay.docx", Data("not really a docx".utf8))
        let board = NSPasteboard(name: NSPasteboard.Name("nomi-attach-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects([document as NSURL])
        board.setData(NSWorkspace.shared.icon(forFile: document.path).tiffRepresentation, forType: .tiff)
        #expect(ChatImages.containsAttachment(board))
        let intake = try #require(ChatImages.intake(pasteboard: board, existing: 0))
        #expect(intake.drafts.count == 1)
        #expect(intake.drafts.first?.isFile == true)
        #expect(intake.drafts.first?.name == "Essay.docx")
        intake.drafts.forEach(ChatImages.discard)
        board.releaseGlobally()
    }

    @Test func foldersAndUnknownFilesGetANote() throws {
        let unknown = try file("song.mp3", Data([0, 1, 2]))
        let result = ChatImages.intake(urls: [folder, unknown], existing: 0)
        #expect(result.drafts.isEmpty)
        #expect(result.notice != nil)
    }
}
