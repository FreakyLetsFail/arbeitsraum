import AppKit
import Foundation
import PDFKit
import Vision
import ZIPFoundation

enum OfficeFileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// Reads only local, expected document entries. No macros, external relationships or remote resources are loaded.
enum OfficeFiles {
    static let supportedExtensions = ["txt", "md", "rtf", "docx", "xlsx", "csv", "tsv", "pdf", "png", "jpg", "jpeg"]
    static func read(_ url: URL, originalName: String) throws -> [WorkspaceFile] {
        let files = try readContents(url, originalName: originalName)
        let characters = files.reduce(0) { $0 + $1.text.utf8.count + $1.rows.reduce(0) { $0 + $1.reduce(0) { $0 + $1.utf8.count } } }
        guard characters <= 8_000_000 else { throw OfficeFileError.message("Der ausgelesene Inhalt überschreitet 8 MB Text.") }
        return files
    }
    private static func readContents(_ url: URL, originalName: String) throws -> [WorkspaceFile] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "md":
            return [.init(name: originalName, kind: .document, text: try String(contentsOf: url, encoding: .utf8))]
        case "rtf":
            let data = try Data(contentsOf: url)
            guard let value = NSAttributedString(rtf: data, documentAttributes: nil) else { throw OfficeFileError.message("RTF konnte nicht gelesen werden.") }
            return [.init(name: originalName, kind: .document, text: value.string, rtf: data)]
        case "csv", "tsv":
            let text = try String(contentsOf: url, encoding: .utf8)
            let separator: Character = ext == "tsv" ? "\t" : (text.components(separatedBy: "\n").first?.contains(";") == true ? ";" : ",")
            return [.init(name: originalName, kind: .table, rows: try delimited(text, separator: separator))]
        case "pdf":
            guard let pdf = PDFDocument(url: url) else { throw OfficeFileError.message("PDF konnte nicht gelesen werden.") }
            guard pdf.pageCount <= 500 else { throw OfficeFileError.message("PDF mit mehr als 500 Seiten wird nicht übernommen.") }
            var text = ""
            for index in 0..<pdf.pageCount {
                text += "\n[Seite \(index + 1)]\n" + (pdf.page(at: index)?.string ?? "")
                guard text.utf8.count <= 2_000_000 else { throw OfficeFileError.message("Der PDF-Text ist zu groß.") }
            }
            let hasText = text.components(separatedBy: .newlines).contains { !$0.hasPrefix("[Seite") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return [.init(name: originalName, kind: .reference, text: hasText ? text : "", importNote: hasText ? "Text aus PDF; Layout und Bilder werden im Chat nicht ausgewertet." : "Kein auslesbarer Text. Gescannte PDFs benötigen OCR; diese Version führt keine PDF-OCR aus.")]
        case "png", "jpg", "jpeg":
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US"]
            try VNImageRequestHandler(url: url).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            return [.init(name: originalName, kind: .reference, text: text, importNote: text.isEmpty ? "Keine Schrift erkannt." : "Auf diesem Mac erkannter Bildtext. Bitte mit dem Original vergleichen.")]
        case "docx": return [try readDOCX(url, name: originalName)]
        case "xlsx": return try readXLSX(url, name: originalName)
        default: throw OfficeFileError.message("Dieses Dateiformat ist noch nicht unterstützt.")
        }
    }

    static func delimited(_ text: String, separator: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text); var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "\"" {
                if quoted && index + 1 < chars.count && chars[index + 1] == "\"" { cell.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if c == separator && !quoted { row.append(cell); cell = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(cell); rows.append(row); row = []; cell = ""
            } else { cell.append(c) }
            guard rows.count <= 10_000, row.count <= 256, cell.utf8.count <= 100_000 else { throw OfficeFileError.message("Tabelle überschreitet die Importgrenze.") }
            index += 1
        }
        guard !quoted else { throw OfficeFileError.message("Nicht geschlossenes Anführungszeichen in CSV.") }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        let width = min(256, rows.map(\.count).max() ?? 1)
        return rows.map { Array($0.prefix(width)) + Array(repeating: "", count: max(0, width - $0.count)) }
    }

    private static func checkedArchive(_ url: URL) throws -> Archive {
        let archive = try Archive(url: url, accessMode: .read)
        var size: UInt64 = 0; var count = 0
        for entry in archive {
            size += entry.uncompressedSize; count += 1
            guard size <= 100_000_000, count <= 5_000 else { throw OfficeFileError.message("Office-Archiv überschreitet die Entpackgrenze.") }
        }
        return archive
    }
    private static func xml(_ archive: Archive, _ path: String, required: Bool = true) throws -> XMLNodeData {
        guard let entry = archive[path] else {
            if !required { return XMLNodeData("empty") }
            throw OfficeFileError.message("Office-Datei ist unvollständig: \(path)")
        }
        guard entry.uncompressedSize <= 20_000_000 else { throw OfficeFileError.message("Office-Inhalt ist zu groß.") }
        var data = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 20_000_000 else { throw OfficeFileError.message("Office-Inhalt ist zu groß.") }
            data.append(chunk)
        }
        guard checksum == entry.checksum else { throw OfficeFileError.message("Prüfsumme des Office-Inhalts stimmt nicht.") }
        return try XMLTree.read(data)
    }

    private static func readDOCX(_ url: URL, name: String) throws -> WorkspaceFile {
        let archive = try checkedArchive(url)
        let root = try xml(archive, "word/document.xml")
        let result = NSMutableAttributedString(string: "")
        for paragraph in root.descendants("p") {
            for run in paragraph.descendants("r") {
                let props = run.children.first { $0.name == "rPr" }
                var traits: NSFontTraitMask = []
                if props?.children.contains(where: { $0.name == "b" && $0.attributes["val"] != "0" }) == true { traits.insert(.boldFontMask) }
                if props?.children.contains(where: { $0.name == "i" && $0.attributes["val"] != "0" }) == true { traits.insert(.italicFontMask) }
                let halfPoints = Double(props?.children.first { $0.name == "sz" }?.attributes["val"] ?? "28") ?? 28
                let size = max(4, min(200, halfPoints / 2))
                let family = props?.children.first { $0.name == "rFonts" }?.attributes["ascii"]
                let base = family.flatMap { NSFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
                let font = NSFontManager.shared.convert(base, toHaveTrait: traits)
                var attrs: [NSAttributedString.Key: Any] = [.font: font]
                if props?.children.contains(where: { $0.name == "u" }) == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                let text = run.children.map { node in node.name == "t" ? node.content : node.name == "tab" ? "\t" : node.name == "br" ? "\n" : "" }.joined()
                result.append(NSAttributedString(string: text, attributes: attrs))
            }
            result.append(NSAttributedString(string: "\n"))
        }
        let rtf = try result.data(from: NSRange(location: 0, length: result.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        return .init(name: name, kind: .document, text: result.string, rtf: rtf, importNote: "DOCX-Text mit einfacher Zeichenformatierung. Tabellen, Kommentare, Bilder und komplexe Layouts werden nicht vollständig übernommen; das Original bleibt im Projekt.")
    }

    private static func readXLSX(_ url: URL, name: String) throws -> [WorkspaceFile] {
        let archive = try checkedArchive(url)
        let strings = try xml(archive, "xl/sharedStrings.xml", required: false).descendants("si").map { $0.descendants("t").map(\.content).joined() }
        let workbook = try xml(archive, "xl/workbook.xml")
        let relationships = try xml(archive, "xl/_rels/workbook.xml.rels")
        let sheets = workbook.descendants("sheet")
        guard sheets.count <= 32 else { throw OfficeFileError.message("Maximal 32 Tabellenblätter pro Import.") }
        return try sheets.map { sheet in
            guard let relation = relationships.descendants("Relationship").first(where: { $0.attributes["Id"] == sheet.attributes["id"] }), relation.attributes["TargetMode"] != "External", let target = relation.attributes["Target"] else { throw OfficeFileError.message("Tabellenblatt-Verknüpfung fehlt.") }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard ModelDownloader.isSafeRelativePath(path) else { throw OfficeFileError.message("Ungültiger Tabellenblatt-Pfad.") }
            let root = try xml(archive, path)
            var cells: [(Int, Int, String)] = []; var height = 0; var width = 0
            for cell in root.descendants("c") {
                guard let ref = cell.attributes["r"], let coordinate = coordinates(ref), coordinate.0 < 10_000, coordinate.1 < 256 else { throw OfficeFileError.message("Tabelle überschreitet 10.000 Zeilen oder 256 Spalten.") }
                let value = cell.children.first { $0.name == "v" }?.content ?? ""
                let formula = cell.children.first { $0.name == "f" }?.content
                let content: String
                if let formula { content = "=" + formula }
                else if cell.attributes["t"] == "s", let index = Int(value), strings.indices.contains(index) { content = strings[index] }
                else if cell.attributes["t"] == "inlineStr" { content = cell.descendants("t").map(\.content).joined() }
                else { content = value }
                cells.append((coordinate.0, coordinate.1, content)); height = max(height, coordinate.0 + 1); width = max(width, coordinate.1 + 1)
                guard height * width <= 100_000 else { throw OfficeFileError.message("Tabelle überschreitet 100.000 Zellen.") }
            }
            var rows = Array(repeating: Array(repeating: "", count: max(width, 1)), count: max(height, 1))
            for (r, c, text) in cells { rows[r][c] = text }
            return .init(name: name + " – " + (sheet.attributes["name"] ?? "Tabelle"), kind: .table, rows: rows, importNote: "Werte und Formeln importiert. Formatierungen, Diagramme, Makros und blattübergreifende Berechnung sind nicht unterstützt.")
        }
    }
    private static func coordinates(_ reference: String) -> (Int, Int)? {
        let letters = reference.prefix(while: { $0.isASCII && $0.isLetter })
        guard !letters.isEmpty, letters.count <= 3, let row = Int(reference.dropFirst(letters.count)), row > 0 else { return nil }
        var column = 0
        for char in letters.uppercased().utf8 { column = column * 26 + Int(char - 64) }
        return (row - 1, column - 1)
    }
    static func writeDOCX(_ file: WorkspaceFile, to url: URL) throws {
        let attr = DocumentContent.attributed(text: file.text, rtf: file.rtf)
        var body = ""
        for paragraph in file.text.components(separatedBy: "\n") {
            body += "<w:p><w:r><w:t xml:space=\"preserve\">\(escape(paragraph))</w:t></w:r></w:p>"
        }
        // Preserve each run's basic character formatting without depending on an external converter.
        if attr.string == file.text {
            body = ""
            var offset = 0
            for paragraph in file.text.components(separatedBy: "\n") {
                body += "<w:p>"
                let length = (paragraph as NSString).length
                attr.enumerateAttributes(in: NSRange(location: offset, length: length)) { attributes, range, _ in
                    let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
                    let traits = NSFontManager.shared.traits(of: font)
                    var props = "<w:rPr><w:rFonts w:ascii=\"\(escape(font.familyName ?? "Arial"))\" w:hAnsi=\"\(escape(font.familyName ?? "Arial"))\"/><w:sz w:val=\"\(Int(font.pointSize * 2))\"/>"
                    if traits.contains(.boldFontMask) { props += "<w:b/>" }; if traits.contains(.italicFontMask) { props += "<w:i/>" }
                    if (attributes[.underlineStyle] as? Int ?? 0) != 0 { props += "<w:u w:val=\"single\"/>" }; props += "</w:rPr>"
                    body += "<w:r>\(props)<w:t xml:space=\"preserve\">\(escape((attr.string as NSString).substring(with: range)))</w:t></w:r>"
                }
                body += "</w:p>"; offset += length + 1
            }
        }
        try archive(url, entries: ["[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>", "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>", "word/document.xml": "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)</w:body></w:document>"])
    }
    static func writeXLSX(_ files: [WorkspaceFile], to url: URL) throws {
        var entries: [String: String] = [:], sheets = "", rels = "", types = ""
        for (index, file) in files.enumerated() {
            let id = index + 1; let name = String(file.name.filter { !"[]:*?/\\".contains($0) }.prefix(24)) + " \(id)"
            sheets += "<sheet name=\"\(escape(name))\" sheetId=\"\(id)\" r:id=\"rId\(id)\"/>"
            rels += "<Relationship Id=\"rId\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(id).xml\"/>"
            types += "<Override PartName=\"/xl/worksheets/sheet\(id).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            var rows = ""
            for (r, values) in file.rows.enumerated() {
                rows += "<row r=\"\(r + 1)\">"
                for (c, value) in values.enumerated() where !value.isEmpty {
                    let ref = SpreadsheetData.columnName(c) + "\(r + 1)"
                    if value.hasPrefix("=") { rows += "<c r=\"\(ref)\"><f>\(escape(String(value.dropFirst())))</f></c>" }
                    else if let number = Double(value), number.isFinite, value.range(of: #"^[+-]?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil, value.filter(\.isNumber).count <= 15 { rows += "<c r=\"\(ref)\"><v>\(escape(value))</v></c>" }
                    else { rows += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>" }
                }
                rows += "</row>"
            }
            entries["xl/worksheets/sheet\(id).xml"] = "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(rows)</sheetData></worksheet>"
        }
        entries["[Content_Types].xml"] = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>\(types)</Types>"
        entries["_rels/.rels"] = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        entries["xl/_rels/workbook.xml.rels"] = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>"
        entries["xl/workbook.xml"] = "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>\(sheets)</sheets><calcPr fullCalcOnLoad=\"1\"/></workbook>"
        try archive(url, entries: entries)
    }
    private static func archive(_ url: URL, entries: [String: String]) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Arbeitsraum-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let zip = try Archive(url: temporary, accessMode: .create)
        for (path, text) in entries {
            let data = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + text).utf8)
            try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        }
        try ExportFileWriter.coordinateWrite(to: url) { coordinatedURL in
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                _ = try FileManager.default.replaceItemAt(coordinatedURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: coordinatedURL)
            }
        }
    }
    private static func escape(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value >= 32 || [9, 10, 13].contains($0.value) }).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum ExportFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        try coordinateWrite(to: url) { coordinatedURL in
            // Avoid atomic Data.write here: its hidden sibling temp file is outside the
            // file-specific sandbox grant returned by NSSavePanel.
            try data.write(to: coordinatedURL)
        }
    }

    static func coordinateWrite(to url: URL, operation: (URL) throws -> Void) throws {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var operationError: Error?
        var didCoordinate = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            didCoordinate = true
            do { try operation(coordinatedURL) } catch { operationError = error }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        guard didCoordinate else { throw CocoaError(.fileWriteUnknown) }
    }
}

private final class XMLNodeData {
    let name: String; let attributes: [String: String]; var content = ""; var children: [XMLNodeData] = []
    init(_ name: String, attributes: [String: String] = [:]) { self.name = name; self.attributes = attributes }
    func descendants(_ name: String) -> [XMLNodeData] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }
}
private final class XMLTree: NSObject, XMLParserDelegate {
    var root = XMLNodeData("root"); var stack: [XMLNodeData] = []; var count = 0; var invalid = false
    static func read(_ data: Data) throws -> XMLNodeData {
        // Reject declarations entirely: document formats here require neither DTDs nor entities.
        guard let prefix = String(data: data, encoding: .utf8) else { throw OfficeFileError.message("Office-XML muss UTF-8 verwenden.") }
        guard !prefix.localizedCaseInsensitiveContains("<!DOCTYPE"), !prefix.localizedCaseInsensitiveContains("<!ENTITY") else { throw OfficeFileError.message("XML mit Entitätsdeklarationen wird nicht geladen.") }
        let delegate = XMLTree(); delegate.stack = [delegate.root]
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.invalid else { throw OfficeFileError.message("Ungültiger oder zu komplexer Office-Inhalt.") }
        return delegate.root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        count += 1
        guard stack.count < 64, count <= 300_000 else { invalid = true; parser.abortParsing(); return }
        let node = XMLNodeData(elementName.components(separatedBy: ":").last!, attributes: Dictionary(attributeDict.map { ($0.key.components(separatedBy: ":").last!, $0.value) }, uniquingKeysWith: { a, _ in a }))
        stack.last?.children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.content += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if stack.count > 1 { stack.removeLast() } }
}
