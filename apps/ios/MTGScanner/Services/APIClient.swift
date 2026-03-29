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

    // MARK: - Single-image route

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

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            data: data,
            filename: filename,
            contentType: contentType,
            promptVersion: promptVersion,
            boundary: boundary
        )

        return try await performRequest(request)
    }

    // MARK: - Batch route (client-side crops)

    /// Uploads multiple pre-cropped images to `/api/v1/recognitions/batch`.
    ///
    /// Each element of `crops` is `(imageData, filename)`. All cropped cards
    /// are merged into a single `RecognitionResult` by the server.
    func recognizeBatch(
        crops: [(data: Data, filename: String)],
        contentType: String = "image/jpeg",
        baseURL: String,
        promptVersion: String = "card-recognition.md"
    ) async throws -> RecognitionResult {
        guard let url = URL(string: baseURL)?.appending(path: "/api/v1/recognitions/batch") else {
            throw APIError.invalidBaseURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeBatchMultipartBody(
            crops: crops,
            contentType: contentType,
            promptVersion: promptVersion,
            boundary: boundary
        )

        return try await performRequest(request)
    }

    // MARK: - Health check

    func checkHealth(baseURL: String) async throws {
        guard let url = URL(string: baseURL),
              url.scheme == "http" || url.scheme == "https" else {
            throw APIError.invalidBaseURL
        }

        let healthURL = url.appending(path: "/health")
        let (_, response) = try await URLSession.shared.data(from: healthURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Printings route

    func fetchPrintings(name: String, baseURL: String) async throws -> [CardPrinting] {
        guard var components = URLComponents(string: baseURL) else {
            throw APIError.invalidBaseURL
        }
        components.path += "/api/v1/cards/printings"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(CardPrintingsResponse.self, from: responseData)
        return decoded.printings
    }

    // MARK: - Shared request helper

    private func performRequest(_ request: URLRequest) async throws -> RecognitionResult {
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

        return try JSONDecoder().decode(RecognitionResult.self, from: responseData)
    }

    // MARK: - Multipart helpers

    private func makeMultipartBody(
        data: Data,
        filename: String,
        contentType: String,
        promptVersion: String,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ string: String) { body.append(Data(string.utf8)) }

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

    private func makeBatchMultipartBody(
        crops: [(data: Data, filename: String)],
        contentType: String,
        promptVersion: String,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"prompt_version\"\r\n\r\n")
        append("\(promptVersion)\r\n")

        for crop in crops {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"images\"; filename=\"\(crop.filename)\"\r\n")
            append("Content-Type: \(contentType)\r\n\r\n")
            body.append(crop.data)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")
        return body
    }
}
