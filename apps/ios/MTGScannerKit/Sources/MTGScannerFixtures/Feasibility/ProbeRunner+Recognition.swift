#if DEBUG
import Foundation
import UIKit

extension ProbeRunner {
    func recognition(_ config: ProbeConfiguration) async {
        for provider in config.providers {
            let keyName = provider.kind.rawValue.uppercased() + "_API_KEY"
            guard let key = ProcessInfo.processInfo.environment[keyName], !key.isEmpty else {
                record(provider.kind.rawValue, ["status": "Unverified", "reason": "No credential supplied"])
                continue
            }
            for filename in config.samples {
                await recognize(provider, key: key, filename: filename)
            }
        }
    }

    private func recognize(_ config: ProbeConfiguration.Provider, key: String, filename: String) async {
        let name = "\(config.kind.rawValue)-\(filename)"
        let start = Date()
        var evidence: [String: Any] = ["status": "Unverified", "model": config.model, "mode": config.mode.rawValue]
        record(name, evidence)
        do {
            let image = try Data(contentsOf: root.appending(path: "samples/" + filename))
            let prompt = try String(contentsOf: root.appending(path: "card-recognition.md"), encoding: .utf8)
            let schema = try Data(contentsOf: root.appending(path: "llm-output.schema.json"))
            let provider = ProbeProvider(kind: config.kind, model: config.model, mode: config.mode)
            let result = try await provider.recognize(key: key, image: image, corner: Self.corner(image),
                                                       prompt: prompt, schemaData: schema, session: session)
            evidence["result"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
            evidence["estimatedCostUSD"] = cost(result.usage, model: config.model)
            evidence["totalTokens"] = result.usage?.totalTokens
            evidence["seconds"] = Date().timeIntervalSince(start)
            evidence["status"] = "Pass"
        } catch { evidence["status"] = "Fail"; evidence["error"] = safeError(error) }
        record(name, evidence)
    }

    static func corner(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let rectangle = CGRect(x: 0, y: Int(Double(cgImage.height) * 0.8),
                               width: cgImage.width / 2, height: Int(Double(cgImage.height) * 0.2))
        guard let crop = cgImage.cropping(to: rectangle) else { return nil }
        return UIImage(cgImage: crop).jpegData(compressionQuality: 0.92)
    }
}
#endif
