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

    func fetchTodayArticle(ignoreCache: Bool = false) async throws -> ArticlePayload {
        var url = Self.todayURL
        if ignoreCache {
            // Cache-bust the CDN (Fastly in front of GitHub Pages); URLRequest
            // cache policy alone only bypasses the local URLCache.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
            url = components.url!
        }
        var request = URLRequest(url: url)
        if ignoreCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let (data, response) = try await URLSession.shared.data(for: request)

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
