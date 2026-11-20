import Foundation
import SwiftData
import Testing
@testable import DailyDose

extension AppTests {
    @Suite struct ModelTests {
        @Test func payloadDecodesSnakeCaseKeysAndAssignsIndices() throws {
            let payload = try JSONDecoder().decode(ArticlePayload.self, from: payloadJSON())
            #expect(payload.fetchDate == "2026-04-09")
            #expect(payload.publishDate == "2024-05-12")
            #expect(payload.sourceUrl == "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC1/")
            #expect(payload.content.map(\.index) == [0, 1, 2, 3, 4])
            #expect(payload.content.map(\.id) == [0, 1, 2, 3, 4])
            #expect(payload.content.map(\.type) == [.heading, .paragraph, .image, .table, .math])
            #expect(payload.content[1].text == "The **cat** sat")
            #expect(payload.content[1].url == nil)
            #expect(payload.content[2].url == "https://cdn.ncbi.nlm.nih.gov/pmc/blobs/a/fig.jpg")
            #expect(payload.content[2].caption == "Fig 1")
            #expect(payload.content[4].mathml == "<math><mi>x</mi></math>")
        }

        @Test func payloadDecodeFailsOnMissingLicense() throws {
            var object = try #require(JSONSerialization.jsonObject(with: payloadJSON()) as? [String: Any])
            object["license"] = nil
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(ArticlePayload.self, from: data) }
        }

        @Test func payloadDecodeFailsOnUnknownBlockType() {
            let data = payloadJSON(content: [["type": "video", "url": "x"]])
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(ArticlePayload.self, from: data) }
        }

        @Test func encodedPayloadRoundTripsThroughArticleContentBlocks() throws {
            let payload = try JSONDecoder().decode(ArticlePayload.self, from: payloadJSON())
            let article = makeArticle(id: "PMC1")
            article.contentJSON = try JSONEncoder().encode(payload)
            let blocks = article.contentBlocks
            #expect(blocks.map(\.type) == payload.content.map(\.type))
            #expect(blocks.map(\.text) == payload.content.map(\.text))
            #expect(blocks.map(\.index) == [0, 1, 2, 3, 4])
        }

        @Test func contentBlocksIsEmptyForEmptyOrGarbageData() {
            let article = makeArticle(id: "PMC1")
            article.contentJSON = Data()
            #expect(article.contentBlocks.isEmpty)
            article.contentJSON = Data("not json".utf8)
            #expect(article.contentBlocks.isEmpty)
        }

        @Test func contentBlocksReflectsReplacedContent() {
            let article = makeArticle(id: "PMC1")
            #expect(article.contentBlocks.count == 5)
            #expect(article.contentBlocks.count == 5)
            article.contentJSON = payloadJSON(content: [["type": "paragraph", "text": "only"]])
            #expect(article.contentBlocks.map(\.text) == ["only"])
        }

        @Test func formattedPublishDate() {
            let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2024, month: 5, day: 12).date!
            let expected = DateFormatter()
            expected.dateStyle = .medium
            #expect(makeArticle(id: "a", publishDate: "2024-05-12").formattedPublishDate == expected.string(from: date))
            #expect(makeArticle(id: "a", publishDate: "2024").formattedPublishDate == "2024")
            #expect(makeArticle(id: "a", publishDate: "").formattedPublishDate == "")
        }

        @Test func formattedFetchDateMatchesPublishDateStyle() {
            let article = makeArticle(id: "a", fetchDate: "2024-05-12", publishDate: "2024-05-12")
            #expect(article.formattedFetchDate == article.formattedPublishDate)
            #expect(article.formattedFetchDate != "2024-05-12")
        }

        @Test func deletingArticleCascadesToItsAnnotations() throws {
            let context = try makeContext()
            let article = makeArticle(id: "PMC1", saved: true)
            context.insert(article)
            for i in 0..<2 {
                let note = makeAnnotation(.text(section: "content", index: i, range: NSRange(location: 0, length: 3)))
                note.article = article
                context.insert(note)
            }
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<Annotation>()) == 2)

            context.delete(article)
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<Annotation>()) == 0)
        }

        @Test func annotationRangeAndScrollID() {
            let a = Annotation(blockIndex: 2, blockSection: BlockSection.footer, startIndex: 4, length: 3, noteText: "n")
            #expect(a.range == NSRange(location: 4, length: 3))
            #expect(a.scrollID == "footer_2")
        }

        @Test func pendingAnnotationKinds() {
            let text = makeAnnotation(.text(section: BlockSection.content, index: 1, range: NSRange(location: 2, length: 3)))
            #expect([text.isTextAnnotation, text.isCellAnnotation, text.isEquationAnnotation] == [true, false, false])

            let cell = makeAnnotation(.cell(index: 3, row: 1, col: 0))
            #expect([cell.isTextAnnotation, cell.isCellAnnotation, cell.isEquationAnnotation] == [false, true, false])
            #expect(cell.blockSection == "content")
            #expect(cell.cellRow == 1 && cell.cellColumn == 0)

            let equation = makeAnnotation(.equation(index: 4))
            #expect([equation.isTextAnnotation, equation.isCellAnnotation, equation.isEquationAnnotation] == [false, false, true])
            #expect(equation.blockSection == "content")
        }

        @Test func zeroLengthTextRangeIsNoAnnotationKind() {
            let a = makeAnnotation(.text(section: "content", index: 0, range: NSRange(location: 5, length: 0)))
            #expect([a.isTextAnnotation, a.isCellAnnotation, a.isEquationAnnotation] == [false, false, false])
        }
    }
}
