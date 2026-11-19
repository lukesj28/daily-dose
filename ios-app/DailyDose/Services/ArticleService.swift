import Foundation

actor ArticleService {
    static let baseURL = "https://lukesj28.github.io/daily-dose"
    static let todayURL = URL(string: baseURL + "/today.json")!

    enum ServiceError: LocalizedError {
        case invalidResponse(Int)
        case decodingFailed(Error)
        case localOverrideNotFound(String)
        case localOverrideReadFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let code):
                return "Server returned status \(code)"
            case .decodingFailed(let error):
                return "Failed to decode article: \(error.localizedDescription)"
            case .localOverrideNotFound(let path):
                return "Local override article file not found at: \(path)"
            case .localOverrideReadFailed(let error):
                return "Failed to read local override article file: \(error.localizedDescription)"
            }
        }
    }

#if DEBUG
    nonisolated(unsafe) static var debugOverridePath: String?

    static func localOverridePath() -> String? {
        if let debugOverridePath { return debugOverridePath }
        if let arg = UserDefaults.standard.string(forKey: "article"), !arg.isEmpty {
            return arg
        }
        let args = ProcessInfo.processInfo.arguments
        for (idx, arg) in args.enumerated() {
            if (arg == "-article" || arg == "--article"), idx + 1 < args.count, !args[idx + 1].isEmpty {
                return args[idx + 1]
            }
            for prefix in ["-article=", "--article=", "-article ", "--article "] where arg.hasPrefix(prefix) {
                let val = String(arg.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        if let env = ProcessInfo.processInfo.environment["DAILY_DOSE_ARTICLE"], !env.isEmpty {
            return env
        }
        return nil
    }

    static func resolveLocalOverrideURL(for path: String) -> URL? {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let projectDir = repoRoot.appendingPathComponent("ios-app")
        trimmed = trimmed
            .replacingOccurrences(of: "$(PROJECT_DIR)", with: projectDir.path)
            .replacingOccurrences(of: "$(SRCROOT)", with: projectDir.path)

        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }

        let inPublic = repoRoot.appendingPathComponent("public").appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: inPublic.path) {
            return inPublic
        }

        let ns = trimmed as NSString
        let name = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "json" : ns.pathExtension
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return bundleURL
        }

        return URL(fileURLWithPath: expanded)
    }
#endif

    func fetchTodayArticle(ignoreCache: Bool = false) async throws -> ArticlePayload {
#if DEBUG
        if let overridePath = Self.localOverridePath() {
            guard let overrideURL = Self.resolveLocalOverrideURL(for: overridePath),
                  FileManager.default.fileExists(atPath: overrideURL.path) else {
                throw ServiceError.localOverrideNotFound(overridePath)
            }
            do {
                let data = try Data(contentsOf: overrideURL)
                return try JSONDecoder().decode(ArticlePayload.self, from: data)
            } catch let error as DecodingError {
                throw ServiceError.decodingFailed(error)
            } catch {
                throw ServiceError.localOverrideReadFailed(error)
            }
        }
#endif

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
