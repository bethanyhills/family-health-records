import UIKit

/// Renders an intake summary as a printable, multi-page US Letter PDF.
enum SummaryPDF {
    static func html(name: String, sections: [SummarySection], generatedOn date: Date = .now) -> String {
        var body = """
        <h1>\(escape(name))</h1>
        <p class="meta">Medical summary · prepared \(escape(date.formatted(date: .long, time: .omitted)))</p>
        """
        for section in sections {
            body += "<h2>\(escape(section.title))</h2>"
            if section.items.isEmpty {
                body += "<p class=\"empty\">\(escape(section.emptyText))</p>"
            } else {
                body += "<table>"
                for item in section.items {
                    body += "<tr><th>\(escape(item.label))</th><td>\(escape(item.value))</td></tr>"
                }
                body += "</table>"
            }
        }
        body += "<p class=\"foot\">Made with Family Health Binder. Please confirm details with the patient or their doctor.</p>"

        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 10.5pt; color: #1a1a1a; }
        h1 { font-size: 20pt; margin: 0 0 2pt; }
        .meta { color: #666; margin: 0 0 12pt; }
        h2 { font-size: 11pt; text-transform: uppercase; letter-spacing: 0.5pt; color: #1a6e80;
             border-bottom: 1pt solid #cfdde0; padding-bottom: 2pt; margin: 14pt 0 4pt; }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; font-weight: 600; width: 38%; vertical-align: top; padding: 2pt 8pt 2pt 0; }
        td { vertical-align: top; padding: 2pt 0; }
        .empty { color: #666; margin: 2pt 0; }
        .foot { color: #888; font-size: 8.5pt; margin-top: 18pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    @MainActor
    static func data(name: String, sections: [SummarySection]) -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(name: name, sections: sections))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, in points
        let margin: CGFloat = 48
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: margin, dy: margin), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextTitle as String: "\(name) medical summary"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Writes the PDF to a temporary, encrypted file for the share sheet.
    @MainActor
    static func file(for person: Person) throws -> URL {
        let safeName = person.displayName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName) - Medical Summary.pdf")
        try data(name: person.displayName, sections: IntakeSummary.sections(for: person))
            .write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
