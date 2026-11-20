import SwiftUI
import UIKit
import WebKit
import Testing
@testable import DailyDose

private let tableHTML = "<table><tr><th>H</th></tr><tr><td>A</td></tr></table>"

@MainActor
private func js(_ webView: WKWebView, _ script: String) async -> String? {
    let value = try? await webView.evaluateJavaScript(script)
    return value as? String
}

@MainActor
private func loadedWebView(in controller: UIViewController) async throws -> WKWebView {
    var found: WKWebView?
    try await waitUntil {
        found = allSubviews(WKWebView.self, in: controller.view).first
        guard let found else { return false }
        return await js(found, "String(document.readyState == 'complete' && document.querySelector('table, math') != null)") == "true"
    }
    return try #require(found)
}

@MainActor
private func hostTable(annotations: [Annotation] = []) async throws -> (UIWindow, WKWebView) {
    let view = TableBlockView(html: tableHTML, annotations: annotations)
        .frame(width: 390, height: 300)
    let (window, controller) = host(view)
    return (window, try await loadedWebView(in: controller))
}

/// Center of table cell (row 1, col 0) in web view coordinates.
@MainActor
private func cellCenter(_ webView: WKWebView) async throws -> CGPoint {
    let script = """
    (function() {
        var r = document.querySelectorAll('tr')[1].querySelectorAll('td, th')[0].getBoundingClientRect();
        return JSON.stringify({x: r.x + r.width / 2, y: r.y + r.height / 2});
    })()
    """
    let json = try #require(await js(webView, script))
    let dict = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Double])
    return CGPoint(x: dict["x"]!, y: dict["y"]!)
}

private let bodyHighlight = "document.body.getAttribute('data-hl') || ''"

private func cellHighlight(row: Int) -> String {
    "document.querySelectorAll('tr')[\(row)].querySelectorAll('td, th')[0].getAttribute('data-hl') || ''"
}

@MainActor @Observable
private final class Holder {
    var annotations: [Annotation] = []
    var tick = 0
}

private struct TableHost: View {
    let holder: Holder
    var body: some View {
        let _ = holder.tick
        TableBlockView(html: tableHTML, annotations: holder.annotations)
            .frame(width: 390, height: 300)
    }
}

private struct MathHost: View {
    let holder: Holder
    var onAnnotate: (() -> Void)?
    var onEdit: ((Annotation) -> Void)?
    var body: some View {
        MathBlockView(mathml: "<math><mi>x</mi></math>", annotation: holder.annotations.first,
                      onAnnotate: onAnnotate, onEditAnnotation: onEdit)
            .frame(width: 390, height: 200)
    }
}

private let decidePolicySelector = Selector(("webView:decidePolicyForNavigationAction:decisionHandler:"))

private final class FakeNavigationAction: WKNavigationAction {
    var type: WKNavigationType = .other
    override var navigationType: WKNavigationType { type }
}

extension AppTests {
    @Suite struct WebBlockTests {

        @Test func tableDisablesContentJavaScriptAndHighlightsAnnotatedCell() async throws {
            let (window, webView) = try await hostTable(annotations: [makeAnnotation(.cell(index: 3, row: 1, col: 0))])
            defer { window.isHidden = true }
            #expect(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)

            let cell = cellHighlight(row: 1)
            try await waitUntil { await js(webView, cell) == "yellow" }
            let other = cellHighlight(row: 0)
            #expect(await js(webView, other) == "")
            let painted = "getComputedStyle(document.querySelectorAll('tr')[1].querySelectorAll('td, th')[0]).boxShadow"
            #expect(await js(webView, painted)?.contains("inset") == true)
        }

        @Test func longPressOnPlainCellRequestsNewAnnotation() async throws {
            let (window, webView) = try await hostTable()
            defer { window.isHidden = true }
            let coordinator = try #require(webView.navigationDelegate as? TableBlockView.Coordinator)
            let tapped = Box<[Int]>()
            coordinator.onAnnotateCell = { tapped.value = [$0, $1] }

            let press = FakeLongPress()
            press.point = try await cellCenter(webView)
            webView.addGestureRecognizer(press)
            coordinator.handleLongPress(press)
            try await waitUntil { tapped.value != nil }
            #expect(tapped.value == [1, 0])
        }

        @Test func longPressOnAnnotatedCellEditsExistingAnnotation() async throws {
            let existing = makeAnnotation(.cell(index: 3, row: 1, col: 0))
            let (window, webView) = try await hostTable(annotations: [existing])
            defer { window.isHidden = true }
            let coordinator = try #require(webView.navigationDelegate as? TableBlockView.Coordinator)
            let edited = Box<Annotation>()
            let annotated = Box<Bool>()
            coordinator.onEditAnnotation = { edited.value = $0 }
            coordinator.onAnnotateCell = { _, _ in annotated.value = true }

            let press = FakeLongPress()
            press.point = try await cellCenter(webView)
            webView.addGestureRecognizer(press)
            coordinator.handleLongPress(press)
            try await waitUntil { edited.value != nil }
            #expect(edited.value?.id == existing.id)
            #expect(annotated.value == nil)
        }

        @Test func tableNavigationPolicyIsRegisteredWithWebKit() async throws {
            let (window, webView) = try await hostTable()
            defer { window.isHidden = true }
            let delegate = try #require(webView.navigationDelegate as? NSObject)
            #expect(delegate.responds(to: decidePolicySelector))
        }

        @Test func tableNavigationOnlyAllowsInitialLoad() async throws {
            let (window, webView) = try await hostTable()
            defer { window.isHidden = true }
            let coordinator = try #require(webView.navigationDelegate as? TableBlockView.Coordinator)
            let action = FakeNavigationAction()

            action.type = .other
            var policy: WKNavigationActionPolicy?
            coordinator.webView(webView, decidePolicyFor: action) { policy = $0 }
            #expect(policy == .allow)

            action.type = .linkActivated
            coordinator.webView(webView, decidePolicyFor: action) { policy = $0 }
            #expect(policy == .cancel)
        }


        @Test func mathIsSandboxedRenderedAndHighlightedWhenAnnotated() async throws {
            let equation = makeAnnotation(.equation(index: 4))
            let view = MathBlockView(mathml: "<math><mi>x</mi></math>", annotation: equation).frame(width: 390, height: 200)
            let (window, controller) = host(view)
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)

            #expect(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
            let csp = "document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content"
            #expect(await js(webView, csp)?.contains("default-src 'none'") == true)
            #expect(await js(webView, "String(document.querySelector('math') != null)") == "true")
            try await waitUntil { await js(webView, bodyHighlight) == "yellow" }
        }

        @Test func mathWithoutAnnotationHasNoHighlight() async throws {
            let view = MathBlockView(mathml: "<math><mi>x</mi></math>").frame(width: 390, height: 200)
            let (window, controller) = host(view)
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)
            #expect(await js(webView, bodyHighlight) == "")
        }


        @Test func tableHighlightFollowsAnnotationsAddedAfterLoad() async throws {
            let holder = Holder()
            let (window, controller) = host(TableHost(holder: holder))
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)
            let cell = cellHighlight(row: 1)

            holder.tick += 1
            holder.annotations = [makeAnnotation(.cell(index: 3, row: 1, col: 0))]
            try await waitUntil { await js(webView, cell) == "yellow" }

            holder.annotations = []
            try await waitUntil { await js(webView, cell) == "" }
        }

        @Test func mathHighlightFollowsAnnotationAddedAndRemoved() async throws {
            let holder = Holder()
            let (window, controller) = host(MathHost(holder: holder))
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)

            holder.annotations = [makeAnnotation(.equation(index: 4))]
            try await waitUntil { await js(webView, bodyHighlight) == "yellow" }
            holder.annotations = []
            try await waitUntil { await js(webView, bodyHighlight) == "" }
        }

        @Test func mathLongPressAnnotatesOrEdits() async throws {
            let holder = Holder()
            let annotated = Box<Bool>()
            let edited = Box<Annotation>()
            let (window, controller) = host(MathHost(holder: holder, onAnnotate: { annotated.value = true }, onEdit: { edited.value = $0 }))
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)
            let coordinator = try #require(webView.navigationDelegate as? NSObject)
            let press = Selector(("handleLongPress:"))

            _ = coordinator.perform(press, with: FakeLongPress())
            #expect(annotated.value == true)
            #expect(edited.value == nil)

            let existing = makeAnnotation(.equation(index: 4))
            holder.annotations = [existing]
            try await waitUntil { await js(webView, bodyHighlight) != "" }
            _ = coordinator.perform(press, with: FakeLongPress())
            #expect(edited.value?.id == existing.id)
        }

        @Test func mathOffersVoiceOverNoteAction() async throws {
            let holder = Holder()
            let annotated = Box<Bool>()
            let edited = Box<Annotation>()
            let (window, controller) = host(MathHost(holder: holder, onAnnotate: { annotated.value = true }, onEdit: { edited.value = $0 }))
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)

            let add = try #require(webView.accessibilityCustomActions?.first)
            #expect(add.name == "Add Note")
            _ = add.actionHandler?(add)
            #expect(annotated.value == true)

            let existing = makeAnnotation(.equation(index: 4))
            holder.annotations = [existing]
            try await waitUntil { webView.accessibilityCustomActions?.first?.name == "Edit Note" }
            let edit = try #require(webView.accessibilityCustomActions?.first)
            _ = edit.actionHandler?(edit)
            #expect(edited.value?.id == existing.id)
        }

        @Test func mathNavigationPolicyIsRegisteredWithWebKit() async throws {
            let (window, controller) = host(MathHost(holder: Holder()))
            defer { window.isHidden = true }
            let webView = try await loadedWebView(in: controller)
            let delegate = try #require(webView.navigationDelegate as? NSObject)
            #expect(delegate.responds(to: decidePolicySelector))
        }
    }
}
