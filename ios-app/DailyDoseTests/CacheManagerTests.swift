import Foundation
import SwiftData
import Testing
@testable import DailyDose

private let currentIdKey = "DailyDose.currentDailyArticleId"

private func articles(_ context: ModelContext) throws -> [Article] {
    try context.fetch(FetchDescriptor<Article>())
}

extension AppTests {
    @Suite struct CacheManagerTests {
        init() { UserDefaults.standard.removeObject(forKey: currentIdKey) }

        @Test func firstFetchInsertsAndPersistsCurrentId() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "PMC1")) }
            let context = try makeContext()
            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)

            #expect(try articles(context).map(\.id) == ["PMC1"])
            #expect(cm.currentDailyId == "PMC1")
            #expect(UserDefaults.standard.string(forKey: currentIdKey) == "PMC1")
            #expect(CacheManager().currentDailyId == "PMC1")
            #expect(cm.isLoading == false)
            #expect(cm.errorMessage == nil)
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func newDailyPurgesOldUnsavedButKeepsLibrary() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "NEW")) }
            let context = try makeContext()
            let old = makeArticle(id: "OLD")
            let lib = makeArticle(id: "LIB", saved: true)
            context.insert(old)
            context.insert(lib)
            for article in [old, lib] {
                let note = makeAnnotation(.text(section: "content", index: 1, range: NSRange(location: 0, length: 3)))
                note.article = article
                context.insert(note)
            }
            try context.save()

            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)

            let remaining = try articles(context)
            #expect(Set(remaining.map(\.id)) == ["NEW", "LIB"])
            #expect(remaining.filter { !$0.isSavedToLibrary }.map(\.id) == ["NEW"])
            #expect(try context.fetchCount(FetchDescriptor<Annotation>()) == 1)
            #expect(remaining.first { $0.id == "LIB" }?.annotations.count == 1)
            #expect(cm.currentDailyId == "NEW")
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func sameIdForcedRefreshOverwritesInPlaceAndKeepsAnnotations() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "A", title: "New title", fetchDate: "2026-04-10")) }
            let context = try makeContext()
            let existing = makeArticle(id: "A", fetchDate: "2026-04-09")
            context.insert(existing)
            let note = makeAnnotation(.text(section: "content", index: 1, range: NSRange(location: 0, length: 3)))
            note.article = existing
            context.insert(note)
            try context.save()

            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context, force: true)

            let rows = try articles(context)
            #expect(rows.count == 1)
            #expect(rows[0].title == "New title")
            #expect(rows[0].annotations.count == 1)
            #expect(rows[0].fetchDate == "2026-04-10")
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func sameIdRefreshPurgesOtherUnsavedDailies() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "A")) }
            let context = try makeContext()
            context.insert(makeArticle(id: "A", saved: true))
            context.insert(makeArticle(id: "B"))
            try context.save()

            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)

            let ids = Set(try articles(context).map(\.id))
            #expect(ids == ["A"])
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func sameIdRefreshLeavesLibraryArticleUntouched() async throws {
            StubURLProtocol.install { _ in (200, payloadJSON(id: "A", title: "New title", fetchDate: "2026-04-10")) }
            let context = try makeContext()
            context.insert(makeArticle(id: "A", saved: true, fetchDate: "2026-04-09"))
            try context.save()

            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context, force: true)

            let row = try #require(try articles(context).first)
            #expect(row.title == "Title A")
            #expect(row.fetchDate == "2026-04-09")
            #expect(cm.currentDailyId == "A")
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func serverErrorWithEmptyStoreIsOffline() async throws {
            StubURLProtocol.install { _ in (500, Data()) }
            let context = try makeContext()
            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isOffline == true)
            #expect(cm.errorMessage == "Server returned status 500")
            #expect(cm.isLoading == false)
        }

        @Test func serverErrorWithCachedDailyIsNotOfflineAndKeepsArticle() async throws {
            StubURLProtocol.install { _ in (500, Data()) }
            let context = try makeContext()
            context.insert(makeArticle(id: "A"))
            try context.save()
            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isOffline == false)
            #expect(try articles(context).map(\.title) == ["Title A"])
        }

        @Test func onlySavedLibraryArticleCountsAsOffline() async throws {
            StubURLProtocol.install { _ in (500, Data()) }
            let context = try makeContext()
            context.insert(makeArticle(id: "LIB", saved: true))
            try context.save()
            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isOffline == true)
        }

        @Test func successfulFetchClearsOfflineState() async throws {
            StubURLProtocol.install { _ in (500, Data()) }
            let context = try makeContext()
            let cm = CacheManager()
            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isOffline == true)

            StubURLProtocol.install { _ in (200, payloadJSON(id: "PMC1")) }
            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isOffline == false)
            #expect(cm.errorMessage == nil)
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func overlappingChecksFetchOnce() async throws {
            StubURLProtocol.install { _ in
                Thread.sleep(forTimeInterval: 0.3)
                return (200, payloadJSON(id: "PMC1"))
            }
            let context = try makeContext()
            let cm = CacheManager()
            let first = Task { await cm.checkAndUpdateCache(context: context) }
            try await waitUntil { cm.isLoading }

            await cm.checkAndUpdateCache(context: context)
            #expect(cm.isLoading == true)
            await first.value
            #expect(StubURLProtocol.requests.count == 1)
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }
    }
}
