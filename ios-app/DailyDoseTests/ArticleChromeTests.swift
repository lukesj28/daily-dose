import SwiftUI
import UIKit
import Testing
@testable import DailyDose

/// Texts of every UITextView in `controller`, top to bottom.
@MainActor
private func texts(in controller: UIViewController, count: Int) async throws -> [String] {
    var result: [String] = []
    try await waitUntil {
        let views = allSubviews(UITextView.self, in: controller.view)
            .sorted { $0.convert($0.bounds, to: controller.view).minY < $1.convert($1.bounds, to: controller.view).minY }
        result = views.map { $0.attributedText.string }
        return result.count == count && !result.contains("")
    }
    return result
}

private func imageBlock(_ url: String?) -> ContentBlock {
    ContentBlock(type: .image, text: nil, url: url, caption: "c", html: nil, mathml: nil)
}

@MainActor
private func height(of url: String?) -> CGFloat {
    let controller = UIHostingController(rootView: ImageBlockView(block: imageBlock(url)))
    return controller.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
}

extension AppTests {
    @Suite struct ArticleChromeTests {
        @Test func footerShowsAuthorsJournalDateAndLicense() async throws {
            let article = makeArticle(id: "PMC1", authors: ["Jane Smith", "John Doe"])
            let (window, controller) = host(ArticleFooterView(article: article))
            defer { window.isHidden = true }
            let lines = try await texts(in: controller, count: 3)
            #expect(lines == ["Jane Smith, John Doe", "Journal of Testing · \(article.formattedPublishDate)", "CC BY"])
        }

        @Test func footerOmitsEmptyAuthorsAndLicense() async throws {
            let article = makeArticle(id: "PMC1", authors: [], license: "")
            let (window, controller) = host(ArticleFooterView(article: article))
            defer { window.isHidden = true }
            let lines = try await texts(in: controller, count: 1)
            #expect(lines == ["Journal of Testing · \(article.formattedPublishDate)"])
        }

        @Test func headerShowsTitleAuthorsAndDate() async throws {
            let article = makeArticle(id: "PMC1", authors: ["Jane Smith", "John Doe"])
            let (window, controller) = host(ArticleHeaderView(article: article))
            defer { window.isHidden = true }
            let lines = try await texts(in: controller, count: 3)
            #expect(lines == ["Title PMC1", "Jane Smith, John Doe", article.formattedPublishDate])
        }

        @Test func imageBlockOnlyRendersHttpsNcbiUrls() {
            StubURLProtocol.install { _ in (404, Data()) }
            #expect(height(of: "https://cdn.ncbi.nlm.nih.gov/x.jpg") >= 100)
            for rejected in ["http://cdn.ncbi.nlm.nih.gov/x.jpg", "https://evil.com/x.jpg",
                             "https://ncbi.nlm.nih.gov.evil.com/x.jpg", nil] {
                #expect(height(of: rejected) == 0)
            }
        }
    }
}
