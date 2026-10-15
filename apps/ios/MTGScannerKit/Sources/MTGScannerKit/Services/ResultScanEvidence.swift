import Foundation
import UIKit

enum ResultScanEvidence {
    static func prepare(base64: String?) -> Data? {
        guard let base64, let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        return prepare(image: image)
    }

    static func prepare(image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, 1000 / max(pixels.width, pixels.height))
        let size = CGSize(width: pixels.width * ratio, height: pixels.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.jpegData(compressionQuality: 0.85)
    }
}

extension CollectionItem {
    var resultScanImage: UIImage? {
        guard collection == nil, deck == nil, let resultScanJPEG else { return nil }
        return UIImage(data: resultScanJPEG)
    }

    func attachResultEvidence(from card: RecognizedCard) {
        guard let jpeg = ResultScanEvidence.prepare(base64: card.cropImageData) else { return }
        do {
            let data = try JSONEncoder().encode(card)
            var snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            // The compressed scan is stored separately; keep recognition metadata immutable.
            snapshot.removeValue(forKey: "crop_image_data")
            originalRecognition = try JSONSerialization.data(withJSONObject: snapshot, options: .sortedKeys)
            resultScanJPEG = jpeg
        } catch {
            print("[Result evidence] Could not encode recognition: \(error)")
        }
    }

    func clearResultEvidence() {
        resultScanJPEG = nil
        originalRecognition = nil
    }
}
