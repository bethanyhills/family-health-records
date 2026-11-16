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
