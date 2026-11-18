import Foundation
import Testing
@testable import DailyDose

extension AppTests {
    @Suite struct ArticleServiceTests {
        @Test func fetchDecodesPayload() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON()) }
            let payload = try await ArticleService().fetchTodayArticle()
            #expect(payload.id == "PMC1")
        }

        @Test func nonSuccessStatusThrowsInvalidResponse() async {
            StubURLProtocol.install { _ in (404, Data()) }
            do {
                _ = try await ArticleService().fetchTodayArticle()
                Issue.record("expected throw")
            } catch let error as ArticleService.ServiceError {
                guard case .invalidResponse(404) = error else { Issue.record("wrong case \(error)"); return }
                #expect(error.errorDescription == "Server returned status 404")
            } catch {
                Issue.record("wrong error \(error)")
            }
        }

        @Test func malformedBodyThrowsDecodingFailed() async {
            StubURLProtocol.install { _ in (200, Data(#"{"id":1}"#.utf8)) }
            do {
                _ = try await ArticleService().fetchTodayArticle()
                Issue.record("expected throw")
            } catch let error as ArticleService.ServiceError {
                guard case .decodingFailed = error else { Issue.record("wrong case \(error)"); return }
                #expect(error.errorDescription?.hasPrefix("Failed to decode article:") == true)
            } catch {
                Issue.record("wrong error \(error)")
            }
        }

        @Test func ignoreCacheAddsTimestampAndBypassesLocalCache() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON()) }
            let before = Int(Date().timeIntervalSince1970)
            _ = try await ArticleService().fetchTodayArticle(ignoreCache: true)
            let after = Int(Date().timeIntervalSince1970)

            let request = try #require(StubURLProtocol.requests.first)
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let t = try #require(items?.first { $0.name == "t" }?.value.flatMap { Int($0) })
            #expect((before...after).contains(t))
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }

        @Test func defaultFetchHasNoQueryAndDefaultCachePolicy() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON()) }
            _ = try await ArticleService().fetchTodayArticle()
            let request = try #require(StubURLProtocol.requests.first)
            #expect(request.url?.query == nil)
            #expect(request.cachePolicy == .useProtocolCachePolicy)
        }
    }
}
