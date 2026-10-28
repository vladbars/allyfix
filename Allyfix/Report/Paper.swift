import AppKit

/// Reports as paper: the Markdown Allyfix writes, laid out as an A4 PDF on the Mac, with
/// no browser and no service.
enum Paper {
    /// A4 in points, and the margin on every side.
    static let size = NSSize(width: 595, height: 842)
    static let margin: CGFloat = 48

    static func pdf(fromMarkdown markdown: String, to file: URL) throws {
        let html = Self.html(markdown)
        guard let text = NSAttributedString(html: Data(html.utf8), documentAttributes: nil) else { throw CocoaError(.fileWriteUnknown) }
        // TextKit 1: TextKit 2 lays tables out as loose lines and draws list markers twice.
        let view = NSTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: size.width - 2 * margin, height: size.height)
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let info = NSPrintInfo()
        info.paperSize = size
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = file
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Just the Markdown these reports use: headings, quotes, lists, tables, bold.
    static func html(_ markdown: String) -> String {
        var body: [String] = []
        var table: [[String]] = []
        var list = false

        func inline(_ text: String) -> String {
            var escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            escaped = escaped.replacing(/\*\*(.+?)\*\*/) { "<b>\($0.output.1)</b>" }
            escaped = escaped.replacing(/`(.+?)`/) { "<code>\($0.output.1)</code>" }
            return escaped
        }
        // Text after a list or a table gets no space above it, so a small empty line stands in.
        let gap = "<p class=gap>&nbsp;</p>"
        func endList() {
            if list { body.append("</ul>" + gap); list = false }
        }
        func flush() {
            endList()
            guard !table.isEmpty else { return }
            let rows = table.filter { !$0.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
            // Two columns: a name and its value; three: a criterion, its level and remarks.
            let widths = rows.first?.count == 3 ? [31, 20, 49] : [22, 78]
            body.append("<table>" + rows.enumerated().map { index, cells in
                let tag = index == 0 ? "th" : "td"
                return "<tr>" + cells.enumerated().map { column, cell in
                    "<\(tag) width=\"\(column < widths.count ? widths[column] : 0)%\">\(inline(cell))</\(tag)>"
                }.joined() + "</tr>"
            }.joined() + "</table>" + gap)
            table = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("|") {
                endList()
                table.append(line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            flush()
            if line.hasPrefix("### ") { body.append("<h3>\(inline(String(line.dropFirst(4))))</h3>") }
            else if line.hasPrefix("## ") { body.append("<h2>\(inline(String(line.dropFirst(3))))</h2>") }
            else if line.hasPrefix("# ") { body.append("<h1>\(inline(String(line.dropFirst(2))))</h1>") }
            else if line.hasPrefix("> ") { body.append("<p class=note>\(inline(String(line.dropFirst(2))))</p>") }
            else if line.hasPrefix("- ") {
                if !list { body.append("<ul>"); list = true }
                body.append("<li>\(inline(String(line.dropFirst(2))))</li>")
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                body.append("<p>\(inline(line))</p>")
            }
        }
        flush()
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 10pt; color: #1d1d1f; }
        h1 { font-size: 18pt; } h2 { font-size: 13pt; margin-top: 16pt; } h3 { font-size: 11pt; margin-top: 12pt; }
        p.note { background: #fff4d6; padding: 6pt; } p.gap { font-size: 9pt; margin: 0; }
        table { border-collapse: collapse; width: 100%; } th, td { border: 0.5pt solid #c7c7cc; padding: 3pt; vertical-align: top; font-size: 8.5pt; text-align: left; }
        th { background: #f2f2f7; } code { font-family: Menlo, monospace; font-size: 8.5pt; }
        </style></head><body>\(body.joined(separator: "\n"))</body></html>
        """
    }
}
