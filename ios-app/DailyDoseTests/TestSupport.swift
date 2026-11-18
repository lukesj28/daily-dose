import Foundation
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import DailyDose

/// Root suite; every suite extends it and the target runs serialized.
@Suite(.serialized) enum AppTests {}


nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []
    nonisolated(unsafe) private static var registered = false

    static var requests: [URLRequest] { lock.withLock { _requests } }

    static func install(handler: Handler?) {
        lock.withLock {
            if !registered {
                URLProtocol.registerClass(StubURLProtocol.self)
                registered = true
            }
            _handler = handler
            _requests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { () -> Handler? in
            Self._requests.append(request)
            return Self._handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}


nonisolated var defaultContent: [[String: Any]] { [
    ["type": "heading", "text": "Intro"],
    ["type": "paragraph", "text": "The **cat** sat"],
    ["type": "image", "url": "https://cdn.ncbi.nlm.nih.gov/pmc/blobs/a/fig.jpg", "caption": "Fig 1"],
    ["type": "table", "html": "<table><tr><th>H</th></tr><tr><td>A</td></tr></table>", "caption": "Table 1"],
    ["type": "math", "mathml": "<math><mi>x</mi></math>"],
] }

nonisolated func payloadJSON(
    id: String = "PMC1",
    title: String = "Title",
    fetchDate: String = "2026-04-09",
    content: [[String: Any]] = defaultContent
) -> Data {
    let object: [String: Any] = [
        "id": id,
        "title": title,
        "journal": "Journal of Testing",
        "fetch_date": fetchDate,
        "publish_date": "2024-05-12",
        "authors": ["Jane Smith"],
        "license": "CC BY",
        "source_url": "https://www.ncbi.nlm.nih.gov/pmc/articles/\(id)/",
        "abstract": "Abstract",
        "content": content,
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

func makeArticle(
    id: String,
    saved: Bool = false,
    fetchDate: String = "2026-04-09",
    authors: [String] = ["Jane Smith"],
    license: String = "CC BY",
    publishDate: String = "2024-05-12"
) -> Article {
    Article(
        id: id,
        title: "Title \(id)",
        journal: "Journal of Testing",
        fetchDate: fetchDate,
        publishDate: publishDate,
        authors: authors,
        license: license,
        sourceUrl: "https://www.ncbi.nlm.nih.gov/pmc/articles/\(id)/",
        abstract: "Abstract",
        contentJSON: payloadJSON(id: id),
        isSavedToLibrary: saved
    )
}

func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Article.self, Annotation.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

/// Keeps every test container alive for the whole run.
@MainActor private var liveContainers: [ModelContainer] = []

@MainActor func makeContext() throws -> ModelContext {
    let container = try makeContainer()
    liveContainers.append(container)
    return container.mainContext
}

func makeAnnotation(_ pending: PendingAnnotation, note: String = "note") -> Annotation {
    Annotation(pending: pending, noteText: note)
}


func host<V: View>(_ view: V, width: CGFloat = 390) -> (UIWindow, UIHostingController<V>) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
    let controller = UIHostingController(rootView: view)
    window.rootViewController = controller
    window.isHidden = false
    window.layoutIfNeeded()
    return (window, controller)
}

func allSubviews<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
    var found: [T] = []
    if let match = root as? T { found.append(match) }
    for child in root.subviews { found += allSubviews(type, in: child) }
    return found
}

func waitUntil(timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("timed out")
}

final class FakeTap: UITapGestureRecognizer {
    var point: CGPoint = .zero
    override func location(in view: UIView?) -> CGPoint { point }
}

final class FakeLongPress: UILongPressGestureRecognizer {
    var point: CGPoint = .zero
    override func location(in view: UIView?) -> CGPoint { point }
    override var state: UIGestureRecognizer.State {
        get { .began }
        set {}
    }
}

@MainActor final class Box<T> { var value: T? }
