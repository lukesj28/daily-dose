import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import DailyDose

private let currentIdKey = "DailyDose.currentDailyArticleId"

private func quoted(_ text: String) -> String { "\u{201C}\(text)\u{201D}" }

private func note(_ section: String, _ index: Int, _ start: Int, _ length: Int = 1) -> Annotation {
    makeAnnotation(.text(section: section, index: index, range: NSRange(location: start, length: length)))
}

@MainActor private func makeCurrent(_ id: String, in context: ModelContext) async -> CacheManager {
    StubURLProtocol.install { _ in (200, payloadJSON(id: id)) }
    let cm = CacheManager()
    await cm.checkAndUpdateCache(context: context)
    return cm
}

extension AppTests {
    @Suite struct ViewFlowTests {
        init() { UserDefaults.standard.removeObject(forKey: currentIdKey) }

        // MARK: CacheManager

        @Test func currentArticleDefaultsToNewestUnsavedWhenNoDailyIsRecorded() {
            let a = makeArticle(id: "A")
            let b = makeArticle(id: "B")
            #expect(CacheManager().currentArticle(in: [a, b]) === a)
            #expect(CacheManager().currentArticle(in: []) == nil)
            #expect(CacheManager().currentArticle(in: [makeArticle(id: "LIB", saved: true)]) == nil)
        }

        @Test func currentArticleIsTheFetchedDaily() async throws {
            let context = try makeContext()
            let a = makeArticle(id: "A")
            let b = makeArticle(id: "B")
            context.insert(a)
            context.insert(b)
            let cm = await makeCurrent("B", in: context)
            #expect(cm.currentArticle(in: [a, b]) === b)
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        @Test func deletingFromLibraryOnlyUnsavesTodaysArticle() async throws {
            let context = try makeContext()
            let current = makeArticle(id: "CUR", saved: true)
            let old = makeArticle(id: "OLD", saved: true)
            context.insert(current)
            context.insert(old)
            let oldNote = makeAnnotation(.text(section: "content", index: 1, range: NSRange(location: 0, length: 3)))
            oldNote.article = old
            context.insert(oldNote)
            let cm = await makeCurrent("CUR", in: context)

            cm.removeFromLibrary(current, context: context)
            cm.removeFromLibrary(old, context: context)
            try context.save()

            let remaining = try context.fetch(FetchDescriptor<Article>())
            #expect(remaining.map(\.id) == ["CUR"])
            #expect(remaining.first?.isSavedToLibrary == false)
            #expect(try context.fetchCount(FetchDescriptor<Annotation>()) == 0)
            UserDefaults.standard.removeObject(forKey: currentIdKey)
        }

        // MARK: Annotation(pending:)

        @Test func textSelectionMapsToAnnotation() {
            let article = makeArticle(id: "A")
            let annotation = Annotation(
                pending: .text(section: "footer", index: 2, range: NSRange(location: 4, length: 3)),
                noteText: "n",
                article: article
            )
            #expect(annotation.blockSection == "footer")
            #expect(annotation.blockIndex == 2)
            #expect(annotation.range == NSRange(location: 4, length: 3))
            #expect(annotation.noteText == "n")
            #expect(annotation.article === article)
        }

        @Test func cellSelectionMapsToCellAnnotation() {
            let annotation = Annotation(pending: .cell(index: 3, row: 1, col: 2), noteText: "n")
            #expect(annotation.cellRow == 1)
            #expect(annotation.cellColumn == 2)
            #expect(annotation.isCellAnnotation)
            #expect(annotation.article == nil)
        }

        // MARK: AnnotationList

        @Test func notesListInReadingOrder() {
            let footer0 = note("footer", 0, 0)
            let content5Late = note("content", 5, 9)
            let header1 = note("header", 1, 0)
            let content5Early = note("content", 5, 2)
            let content1 = note("content", 1, 0)
            let sorted = AnnotationList.sorted([footer0, content5Late, header1, content5Early, content1])
            #expect(sorted.map(\.id) == [header1, content1, content5Early, content5Late, footer0].map(\.id))
        }

        @Test func annotationSnippetQuotesHeaderAndFooterText() {
            let article = makeArticle(id: "PMC1", authors: ["Jane Smith"])
            #expect(AnnotationList.snippet(for: note("header", 1, 0, 5), in: article) == quoted("Title"))
            #expect(AnnotationList.snippet(for: note("footer", 2, 0, 2), in: article) == quoted("CC"))
        }

        @Test func annotationSnippetQuotesCaptionOfImageBlock() {
            let article = makeArticle(id: "PMC1")
            #expect(AnnotationList.snippet(for: note("content", 2, 0, 3), in: article) == quoted("Fig"))
        }

        @Test func annotationSnippetShowsTheSelectedTextOfMarkdownParagraph() {
            let article = makeArticle(id: "PMC1")
            #expect(AnnotationList.snippet(for: note("content", 1, 4, 3), in: article) == quoted("cat"))
        }

        @Test func annotationSnippetLabelsCellsAndEquations() {
            let article = makeArticle(id: "PMC1")
            let cell = makeAnnotation(.cell(index: 3, row: 0, col: 1))
            let equation = makeAnnotation(.equation(index: 4))
            #expect(AnnotationList.snippet(for: cell, in: article) == "Table cell (1, 2)")
            #expect(AnnotationList.snippet(for: equation, in: article) == "Equation")
        }

        @Test func annotationSnippetIsNilForOutOfRangeSelections() {
            let article = makeArticle(id: "PMC1")
            #expect(AnnotationList.snippet(for: note("content", 1, 100, 3), in: article) == nil)
            #expect(AnnotationList.snippet(for: note("header", 9, 0, 3), in: article) == nil)
        }

        @Test func annotationSnippetTruncatesAtEightyCharacters() {
            let article = makeArticle(id: "PMC1")
            article.contentJSON = payloadJSON(content: [["type": "paragraph", "text": String(repeating: "a", count: 100)]])
            let expected = quoted(String(repeating: "a", count: 80) + "…")
            #expect(AnnotationList.snippet(for: note("content", 0, 0, 100), in: article) == expected)
        }

        @Test func searchStepWrapsInBothDirections() {
            #expect(AnnotationList.step(0, by: -1, count: 3) == 2)
            #expect(AnnotationList.step(2, by: 1, count: 3) == 0)
            #expect(AnnotationList.step(1, by: 1, count: 3) == 2)
            #expect(AnnotationList.step(0, by: 1, count: 0) == nil)
        }

        // MARK: FABPosition

        @Test func fabSnapsToNearestCorner() {
            let frame = CGRect(x: 0, y: 0, width: 400, height: 800)
            #expect(FABPosition.nearest(to: CGPoint(x: 10, y: 10), in: frame) == .topLeft)
            #expect(FABPosition.nearest(to: CGPoint(x: 390, y: 10), in: frame) == .topRight)
            #expect(FABPosition.nearest(to: CGPoint(x: 10, y: 790), in: frame) == .bottomLeft)
            #expect(FABPosition.nearest(to: CGPoint(x: 390, y: 790), in: frame) == .bottomRight)
            #expect(FABPosition.nearest(to: CGPoint(x: 200, y: 400), in: frame) == .bottomRight)
        }
    }
}
