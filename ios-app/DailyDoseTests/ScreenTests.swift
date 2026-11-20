import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import DailyDose

private let currentIdKey = "DailyDose.currentDailyArticleId"

@MainActor
private func renderedTexts(_ controller: UIViewController) -> [String] {
    allSubviews(UITextView.self, in: controller.view).map { $0.attributedText.string }
}

@MainActor
private func waitForTexts(_ controller: UIViewController, _ expected: [String]) async throws {
    try await waitUntil { Set(expected).isSubset(of: Set(renderedTexts(controller))) }
}

@MainActor
private func hostDaily(_ context: ModelContext, _ cacheManager: CacheManager) -> (UIWindow, UIHostingController<some View>) {
    host(DailyView()
        .modelContainer(context.container)
        .environment(cacheManager)
        .environment(SaveNotifier()))
}

extension AppTests {
    @Suite struct ScreenTests {
        init() { UserDefaults.standard.removeObject(forKey: currentIdKey) }

        @Test func dailyScreenShowsTheFetchedArticle() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "D1")) }
            let context = try makeContext()
            let (window, controller) = hostDaily(context, CacheManager())
            defer { window.isHidden = true; UserDefaults.standard.removeObject(forKey: currentIdKey) }

            try await waitForTexts(controller, ["Title", "Intro", "The cat sat"])
            #expect(try context.fetchCount(FetchDescriptor<Article>()) == 1)
        }

        @Test func dailyScreenKeepsShowingTodaysArticleAfterItLeavesTheLibrary() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "CUR", title: "Today")) }
            let context = try makeContext()
            let current = makeArticle(id: "CUR", saved: true)
            context.insert(current)
            try context.save()
            let cacheManager = CacheManager()
            let (window, controller) = hostDaily(context, cacheManager)
            defer { window.isHidden = true; UserDefaults.standard.removeObject(forKey: currentIdKey) }
            try await waitForTexts(controller, ["Title CUR"])

            cacheManager.removeFromLibrary(current, context: context)
            try context.save()

            try await waitForTexts(controller, ["Title CUR", "The cat sat"])
            #expect(current.isSavedToLibrary == false)
        }

        @Test func readerScreenShowsSavedArticleContent() async throws {
            let context = try makeContext()
            let article = makeArticle(id: "LIB", saved: true)
            context.insert(article)
            try context.save()
            let view = NavigationStack { ArticleReaderView(article: article) }
                .modelContainer(context.container)
                .environment(CacheManager())
            let (window, controller) = host(view)
            defer { window.isHidden = true }

            try await waitForTexts(controller, ["Title LIB", "Intro", "The cat sat"])
        }

        @Test func readerSurvivesItsArticleBeingDeleted() async throws {
            let context = try makeContext()
            let article = makeArticle(id: "GONE", saved: false)
            context.insert(article)
            try context.save()
            let view = NavigationStack { ArticleReaderView(article: article) }
                .modelContainer(context.container)
                .environment(CacheManager())
            let (window, controller) = host(view)
            defer { window.isHidden = true }
            try await waitForTexts(controller, ["Title GONE"])

            context.delete(article)
            try context.save()
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
        }
    }
}
