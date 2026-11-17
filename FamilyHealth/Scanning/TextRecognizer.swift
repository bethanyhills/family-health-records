import UIKit
import Vision

/// Reads printed text from a photo with Apple's on-device text recognition.
/// Nothing is sent off the phone.
enum TextRecognizer {
    static func lines(in imageData: Data) async -> [String] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { return [] }
        let orientation = image.cgOrientation
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Member IDs and Rx codes aren't words; don't "fix" them.
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            let observations = request.results ?? []
            // Top-to-bottom, then left-to-right, so labels come before their values.
            let sorted = observations.sorted {
                let a = $0.boundingBox, b = $1.boundingBox
                if abs(a.midY - b.midY) > 0.02 { return a.midY > b.midY }
                return a.minX < b.minX
            }
            return sorted.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    /// Text read row by row, the way a table reads across: pieces that sit side by side
    /// are joined into one line. Used for vaccine records, where a row is a vaccine and its dates.
    static func rows(in imageData: Data) async -> [String] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { return [] }
        let orientation = image.cgOrientation
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            let pieces = (request.results ?? []).compactMap { observation -> TextPiece? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return TextPiece(text: text, box: observation.boundingBox)
            }
            return TextPiece.rows(pieces)
        }.value
    }
}

/// A piece of recognized text and where it sits (Vision coordinates: 0...1, origin bottom left).
struct TextPiece {
    let text: String
    let box: CGRect

    /// Groups pieces whose middles line up into rows, top to bottom, each read left to right.
    static func rows(_ pieces: [TextPiece]) -> [String] {
        var rows: [[TextPiece]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = rows.last?.first,
               abs(first.box.midY - piece.box.midY) < max(first.box.height, piece.box.height) * 0.6 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
