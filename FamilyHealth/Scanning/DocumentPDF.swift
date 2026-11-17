import PDFKit
import UIKit

/// Turns scans and photos into one PDF, and reads the text of a PDF on the phone.
enum DocumentPDF {
    /// Letter width in points; each page keeps its picture's shape.
    static let pageWidth: CGFloat = 612

    static func pdf(from images: [UIImage]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageWidth * 11 / 8.5))
        return renderer.pdfData { context in
            for image in images where image.size.width > 0 && image.size.height > 0 {
                let height = pageWidth * image.size.height / image.size.width
                let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: height)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }
    }

    static func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    /// The PDF's own text if it has any (most emailed reports), otherwise text read from
    /// pictures of its first pages with on-device text recognition.
    static func text(of data: Data, maxScannedPages: Int = 20) async -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        let embedded = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if embedded.count > 20 { return embedded }
        var lines: [String] = []
        for index in 0..<min(document.pageCount, maxScannedPages) {
            guard let page = document.page(at: index),
                  let jpeg = image(of: page, width: 1600).jpegData(compressionQuality: 0.8)
            else { continue }
            lines += await TextRecognizer.lines(in: jpeg)
        }
        return lines.joined(separator: "\n")
    }

    static func thumbnail(of data: Data, width: CGFloat = 120) -> UIImage? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        return image(of: page, width: width)
    }

    private static func image(of page: PDFPage, width: CGFloat) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = width / max(bounds.width, 1)
        return page.thumbnail(of: CGSize(width: width, height: bounds.height * scale), for: .mediaBox)
    }
}
