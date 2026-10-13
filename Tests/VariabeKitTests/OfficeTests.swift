import Foundation
import Testing
@testable import VariabeKit

@Suite struct OfficeTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Variabe SearchTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Zips `parts` (path in the zip → contents) with /usr/bin/zip, deflated as Office saves them.
    func office(_ name: String, _ parts: [String: String]) throws -> URL {
        let source = folder.appendingPathComponent(UUID().uuidString)
        for (path, contents) in parts {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        let out = folder.appendingPathComponent(name)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = source
        zip.arguments = ["-q", "-r", "-9", out.path, "."]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        return out
    }

    static let a = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main""#
    static let r = #"xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#

    static func slide(_ paragraphs: [String]) -> String {
        let body = paragraphs.map { "<a:p><a:r><a:t>\($0)</a:t></a:r></a:p>" }.joined()
        return "<p:sld xmlns:p=\"p\" \(a)><p:cSld><p:spTree><p:sp><p:txBody>\(body)</p:txBody></p:sp></p:spTree></p:cSld></p:sld>"
    }

    @Test func slidesInShowOrderWithNotes() throws {
        // slide2.xml is shown first: the order comes from presentation.xml, not the file names.
        let url = try office("deck.pptx", [
            "ppt/presentation.xml": """
                <p:presentation xmlns:p="p" \(Self.r)><p:sldIdLst>
                <p:sldId id="256" r:id="rId3"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst></p:presentation>
                """,
            "ppt/_rels/presentation.xml.rels": """
                <Relationships><Relationship Id="rId2" Target="slides/slide1.xml"/>
                <Relationship Id="rId3" Target="/ppt/slides/slide2.xml"/></Relationships>
                """,
            "ppt/slides/slide1.xml": Self.slide(["Quarterly revenue", "Up 12% in Kenya"]),
            "ppt/slides/slide2.xml": Self.slide(["Agenda"]),
            "ppt/slides/_rels/slide1.xml.rels": """
                <Relationships><Relationship Id="rId1" Target="../notesSlides/notesSlide1.xml"/></Relationships>
                """,
            "ppt/notesSlides/notesSlide1.xml": """
                <p:notes xmlns:p="p" \(Self.a)><a:p><a:r><a:t>Mention the M-Pesa partnership</a:t></a:r></a:p>
                <a:p><a:fld id="x" type="slidenum"><a:t>2</a:t></a:fld></a:p></p:notes>
                """,
        ])
        let slides = try OfficeExtractor.slides(of: url)
        #expect(slides == ["Slide 1\nAgenda",
                           "Slide 2\nQuarterly revenue\nUp 12% in Kenya\nNotes: Mention the M-Pesa partnership"])
        let pieces = try DocExtractor.pieces(of: url, limit: 100).chunks
        #expect(pieces.count == 2)
    }

    @Test func sheetsInWorkbookOrder() throws {
        let url = try office("budget.xlsx", [
            "xl/workbook.xml": """
                <workbook \(Self.r)><sheets><sheet name="Summary" sheetId="2" r:id="rId9"/>
                <sheet name="Raw data" sheetId="1" r:id="rId1"/></sheets></workbook>
                """,
            "xl/_rels/workbook.xml.rels": """
                <Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/>
                <Relationship Id="rId9" Target="worksheets/sheet2.xml"/></Relationships>
                """,
            "xl/sharedStrings.xml": """
                <sst><si><t>Region</t></si><si><t>Revenue</t></si><si><r><t>Nai</t></r><r><t>robi</t></r>
                <rPh><t>ignored</t></rPh></si></sst>
                """,
            "xl/worksheets/sheet1.xml": """
                <worksheet><sheetData>
                <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
                <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><f>SUM(C2:D2)</f><v>1250.5</v></c></row>
                <row r="3"/>
                </sheetData></worksheet>
                """,
            "xl/worksheets/sheet2.xml": """
                <worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Total</t></is></c>
                <c r="B1" t="b"><v>1</v></c></row></sheetData></worksheet>
                """,
        ])
        let sheets = try OfficeExtractor.sheets(of: url, limit: 100_000)
        #expect(sheets.map(\.name) == ["Summary", "Raw data"])
        #expect(sheets[0].body == "Total | TRUE")
        #expect(sheets[1].header == "Region | Revenue")
        #expect(sheets[1].body == "Region | Revenue\nNairobi | 1250.5")
        let pieces = try DocExtractor.pieces(of: url, limit: 100).chunks
        #expect(pieces == ["Sheet: Summary\nTotal | TRUE", "Sheet: Raw data\nRegion | Revenue\nNairobi | 1250.5"])
    }

    @Test func longSheetPiecesKeepTheirHeader() throws {
        let rows = (1...400).map { "<row><c t=\"inlineStr\"><is><t>Customer number \($0) paid late</t></is></c></row>" }
        let url = try office("long.xlsx", [
            "xl/workbook.xml": "<workbook \(Self.r)><sheets><sheet name=\"Log\" r:id=\"rId1\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
            "xl/worksheets/sheet1.xml": "<worksheet><sheetData>" + rows.joined() + "</sheetData></worksheet>",
        ])
        let pieces = try DocExtractor.pieces(of: url, limit: 100).chunks
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.hasPrefix("Sheet: Log\n") })
        #expect(pieces.dropFirst().allSatisfy { $0.hasPrefix("Sheet: Log\nCustomer number 1 paid late\n") })
    }

    @Test func notAZipIsUnreadable() throws {
        let file = folder.appendingPathComponent("broken.pptx")
        try "not a zip".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: ExtractError.self) { try OfficeExtractor.slides(of: file) }
    }

    @Test func officeFilesAreDocumentsButLockFilesAreNot() {
        let options = IndexOptions()
        for name in ["deck.pptx", "budget.xlsx"] {
            #expect(Rules.classify(folder.appendingPathComponent(name), type: nil, options: options) == .index(.doc))
        }
        #expect(Rules.classify(folder.appendingPathComponent("~$deck.pptx"), type: nil, options: options)
                == .skip("Office lock file"))
    }

    @Test func relationshipTargets() {
        #expect(OfficeExtractor.resolve("../notesSlides/notesSlide1.xml", from: "ppt/slides")
                == "ppt/notesSlides/notesSlide1.xml")
        #expect(OfficeExtractor.resolve("/xl/worksheets/sheet1.xml", from: "xl") == "xl/worksheets/sheet1.xml")
    }
}
