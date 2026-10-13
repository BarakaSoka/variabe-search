import Compression
import Foundation

/// PowerPoint (.pptx) and Excel (.xlsx): zip files of XML (Office Open XML), which the Cocoa text system can't read.
/// Slides come in the order the presentation shows them, each with its speaker notes; sheets in the workbook's order,
/// row by row, with cells separated by " | ". The older binary .ppt and .xls aren't read.
enum OfficeExtractor {
    /// One string per slide that has text: "Slide 3" on its first line, then its text, then "Notes: …".
    static func slides(of url: URL) throws -> [String] {
        let zip = try ZipArchive(url)
        var paths: [String] = []
        if let presentation = zip.text("ppt/presentation.xml") {
            let rels = relationships(zip, of: "ppt/presentation.xml")
            var ids: [String] = []
            XMLWalker.walk(presentation, start: { name, attributes in
                if name == "sldId", let id = relationshipID(attributes) { ids.append(id) }
            })
            paths = ids.compactMap { rels[$0] }
        }
        if paths.isEmpty {   // No presentation part to order them by: the slides as numbered.
            paths = zip.names.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        var slides: [String] = []
        for (index, path) in paths.enumerated() {
            guard let xml = zip.text(path) else { continue }
            var text = paragraphs(xml)
            if let notesPath = relationships(zip, of: path).first(where: { $0.value.contains("notesSlide") })?.value,
               let notesXML = zip.text(notesPath) {
                let notes = paragraphs(notesXML, skipFields: true)
                if !notes.isEmpty { text += (text.isEmpty ? "" : "\n") + "Notes: " + notes }
            }
            if !text.isEmpty { slides.append("Slide \(index + 1)\n" + text) }
        }
        return slides
    }

    struct Sheet {
        let name: String
        let header: String?   // the first row with anything in it
        let body: String      // all its rows, one per line (the header included)
    }

    /// The workbook's sheets that have anything in them. Formulas give their last computed value; dates are the
    /// serial numbers Excel stores. Stops reading once `limit` characters are in.
    static func sheets(of url: URL, limit: Int) throws -> [Sheet] {
        let zip = try ZipArchive(url)
        var shared: [String] = []
        if let xml = zip.text("xl/sharedStrings.xml") {
            var current = "", inText = false, inPhonetic = false
            XMLWalker.walk(xml, start: { name, _ in
                switch name {
                case "si": current = ""
                case "rPh": inPhonetic = true
                case "t": inText = !inPhonetic
                default: break
                }
            }, end: { name in
                switch name {
                case "si": shared.append(current)
                case "rPh": inPhonetic = false
                case "t": inText = false
                default: break
                }
                return true
            }, text: { if inText { current += $0 } })
        }
        var order: [(name: String, path: String)] = []
        if let workbook = zip.text("xl/workbook.xml") {
            let rels = relationships(zip, of: "xl/workbook.xml")
            XMLWalker.walk(workbook, start: { name, attributes in
                if name == "sheet", let id = relationshipID(attributes), let path = rels[id] {
                    order.append((attributes["name"] ?? "Sheet \(order.count + 1)", path))
                }
            })
        }
        var sheets: [Sheet] = []
        var total = 0
        for (name, path) in order {
            guard total < limit, let xml = zip.text(path) else { continue }
            var rows: [String] = [], cells: [String] = []
            var type = "", value = "", inValue = false, inInline = false
            XMLWalker.walk(xml, start: { element, attributes in
                switch element {
                case "row": cells = []
                case "c": (type, value) = (attributes["t"] ?? "n", "")
                case "v": inValue = true
                case "is": inInline = true
                case "t": inValue = inInline
                default: break
                }
            }, end: { element in
                switch element {
                case "v", "t": inValue = false
                case "is": inInline = false
                case "c":
                    var cell = value
                    if type == "s", let index = Int(value), shared.indices.contains(index) { cell = shared[index] }
                    if type == "b" { cell = value == "1" ? "TRUE" : "FALSE" }
                    cell = cell.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if !cell.isEmpty { cells.append(cell) }
                case "row":
                    if !cells.isEmpty {
                        let row = cells.joined(separator: " | ")
                        rows.append(row)
                        total += row.count + 1
                    }
                    return total < limit
                default: break
                }
                return true
            }, text: { if inValue { value += $0 } })
            if !rows.isEmpty { sheets.append(Sheet(name: name, header: rows.first, body: rows.joined(separator: "\n"))) }
        }
        return sheets
    }

    /// A part's text, a line per paragraph (`a:p`). `skipFields`: leave out fields (`a:fld`), as the slide number a
    /// notes page shows.
    private static func paragraphs(_ xml: String, skipFields: Bool = false) -> String {
        var lines: [String] = [], line = "", inText = false, inField = false
        XMLWalker.walk(xml, start: { name, _ in
            if name == "t" { inText = true }
            if name == "fld" { inField = true }
        }, end: { name in
            switch name {
            case "t": inText = false
            case "fld": inField = false
            case "p":
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
                line = ""
            default: break
            }
            return true
        }, text: { if inText, !(skipFields && inField) { line += $0 } })
        return lines.joined(separator: "\n")
    }

    /// A part's relationships (`_rels/<name>.rels`): id → the target's path in the zip.
    private static func relationships(_ zip: ZipArchive, of part: String) -> [String: String] {
        let folder = (part as NSString).deletingLastPathComponent
        let relsPath = (folder.isEmpty ? "" : folder + "/") + "_rels/" + (part as NSString).lastPathComponent + ".rels"
        guard let xml = zip.text(relsPath) else { return [:] }
        var map: [String: String] = [:]
        XMLWalker.walk(xml, start: { name, attributes in
            guard name == "Relationship", let id = attributes["Id"], let target = attributes["Target"],
                  attributes["TargetMode"] != "External" else { return }
            map[id] = resolve(target, from: folder)
        })
        return map
    }

    /// The `r:id` of an element (its namespace prefix may be any).
    private static func relationshipID(_ attributes: [String: String]) -> String? {
        attributes.first { $0.key.hasSuffix(":id") }?.value
    }

    /// A relationship target ("slides/slide1.xml", "../notesSlides/notesSlide1.xml", "/ppt/slides/slide1.xml") as a
    /// path in the zip.
    static func resolve(_ target: String, from folder: String) -> String {
        var parts = target.hasPrefix("/") ? [] : folder.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/") {
            switch piece {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(piece))
            }
        }
        return parts.joined(separator: "/")
    }
}

/// Element starts, ends and text, by local name (the namespace prefix dropped). `end` returning false stops reading.
final class XMLWalker: NSObject, XMLParserDelegate {
    private let start: (String, [String: String]) -> Void
    private let end: (String) -> Bool
    private let text: (String) -> Void

    private init(start: @escaping (String, [String: String]) -> Void, end: @escaping (String) -> Bool,
                 text: @escaping (String) -> Void) {
        (self.start, self.end, self.text) = (start, end, text)
    }

    static func walk(_ xml: String, start: @escaping (String, [String: String]) -> Void = { _, _ in },
                     end: @escaping (String) -> Bool = { _ in true }, text: @escaping (String) -> Void = { _ in }) {
        let parser = XMLParser(data: Data(xml.utf8))
        let walker = XMLWalker(start: start, end: end, text: text)
        parser.delegate = walker
        parser.parse()
    }

    private static func local(_ name: String) -> String {
        name.firstIndex(of: ":").map { String(name[name.index(after: $0)...]) } ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        start(Self.local(elementName), attributes)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if !end(Self.local(elementName)) { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text(string) }
}

/// Reads the files in a zip: stored or deflated, no zip64 (Office files never need it), no encryption.
struct ZipArchive {
    private let bytes: [UInt8]
    private var entries: [String: (offset: Int, method: Int, compressed: Int, size: Int)] = [:]
    /// No single part gets bigger than this when inflated: a zip bomb can't take the memory.
    static let maxPart = 256 << 20

    var names: [String] { Array(entries.keys) }

    init(_ url: URL) throws {
        bytes = [UInt8](try Data(contentsOf: url, options: .mappedIfSafe))
        // The end of central directory record, in the last 64 KiB (+ its 22 bytes).
        var end = -1
        var at = bytes.count - 22
        while at >= max(0, bytes.count - 22 - 65_535) {
            if u32(at) == 0x0605_4b50 { end = at; break }
            at -= 1
        }
        guard end >= 0 else { throw ExtractError.unreadable("not a zip file") }
        let count = u16(end + 10)
        var entry = Int(u32(end + 16))
        for _ in 0..<count {
            guard entry + 46 <= bytes.count, u32(entry) == 0x0201_4b50 else {
                throw ExtractError.unreadable("damaged zip directory")
            }
            let nameLength = u16(entry + 28), extraLength = u16(entry + 30), commentLength = u16(entry + 32)
            guard entry + 46 + nameLength <= bytes.count else { throw ExtractError.unreadable("damaged zip directory") }
            let name = String(decoding: bytes[(entry + 46)..<(entry + 46 + nameLength)], as: UTF8.self)
            entries[name] = (Int(u32(entry + 42)), u16(entry + 10), Int(u32(entry + 20)), Int(u32(entry + 24)))
            entry += 46 + nameLength + extraLength + commentLength
        }
    }

    /// A part as UTF-8 text, or nil when it's missing or can't be read.
    func text(_ name: String) -> String? {
        data(name).map { String(decoding: $0, as: UTF8.self) }
    }

    func data(_ name: String) -> [UInt8]? {
        guard let entry = entries[name], entry.size <= Self.maxPart, entry.offset + 30 <= bytes.count,
              u32(entry.offset) == 0x0403_4b50 else { return nil }
        let start = entry.offset + 30 + u16(entry.offset + 26) + u16(entry.offset + 28)
        guard start + entry.compressed <= bytes.count else { return nil }
        let source = bytes[start..<(start + entry.compressed)]
        switch entry.method {
        case 0: return Array(source)
        case 8:
            guard entry.size > 0 else { return [] }
            var out = [UInt8](repeating: 0, count: entry.size)
            // COMPRESSION_ZLIB is raw deflate, as zip stores it.
            let written = source.withUnsafeBufferPointer { input in
                compression_decode_buffer(&out, entry.size, input.baseAddress!, entry.compressed, nil,
                                          COMPRESSION_ZLIB)
            }
            return written == entry.size ? out : nil
        default: return nil
        }
    }

    private func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    private func u32(_ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
