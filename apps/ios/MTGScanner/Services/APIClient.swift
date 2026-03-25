import Foundation

struct APIClient {
    enum APIError: LocalizedError {
        case invalidBaseURL
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "The API base URL is invalid."
            case .invalidResponse:
                return "The API response was invalid."
            }
        }
    }

    func recognizeImage(
        data: Data,
        filename: String,
        contentType: String,
        baseURL: String,
        promptVersion: String = "card-recognition.md"
    ) async throws -> RecognitionResult {
        guard let url = URL(string: baseURL)?.appending(path: "/api/v1/recognitions") else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            data: data,
            filename: filename,
            contentType: contentType,
            promptVersion: promptVersion,
            boundary: boundary
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: responseData, encoding: .utf8)
            throw NSError(
                domain: "MTGScanner.APIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: serverMessage ?? "Request failed."]
            )
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RecognitionResult.self, from: responseData)
    }

    private func makeMultipartBody(
        data: Data,
        filename: String,
        contentType: String,
        promptVersion: String,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"prompt_version\"\r\n\r\n")
        append("\(promptVersion)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }
}
