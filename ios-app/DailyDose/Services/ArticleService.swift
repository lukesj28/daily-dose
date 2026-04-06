import Foundation

actor ArticleService {
    static let todayURL = URL(string: "https://lukesj28.github.io/daily-dose/today.json")!

    enum ServiceError: LocalizedError {
        case invalidResponse(Int)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let code):
                return "Server returned status \(code)"
            case .decodingFailed(let error):
                return "Failed to decode article: \(error.localizedDescription)"
            }
        }
    }

    func fetchTodayArticle() async throws -> ArticlePayload {
        let (data, response) = try await URLSession.shared.data(from: Self.todayURL)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw ServiceError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ArticlePayload.self, from: data)
        } catch {
            throw ServiceError.decodingFailed(error)
        }
    }
}
