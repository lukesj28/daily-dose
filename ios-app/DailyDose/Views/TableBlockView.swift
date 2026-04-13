import SwiftUI
import WebKit

struct TableBlockView: UIViewRepresentable {
    let html: String
    @Binding var isScrolling: Bool
    var annotations: [Annotation] = []
    var highlightColorR: Double = 1.0
    var highlightColorG: Double = 0.93
    var highlightColorB: Double = 0.27
    var onAnnotateCell: ((Int, Int) -> Void)? = nil
    var onEditAnnotation: ((Annotation) -> Void)? = nil
    var onDeleteAnnotation: ((Annotation) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = true
        webView.scrollView.bounces = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        webView.addGestureRecognizer(longPress)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollBegan = { isScrolling = true }
        context.coordinator.onScrollEnded = { isScrolling = false }
        context.coordinator.annotations = annotations
        context.coordinator.highlightColorR = highlightColorR
        context.coordinator.highlightColorG = highlightColorG
        context.coordinator.highlightColorB = highlightColorB
        context.coordinator.onAnnotateCell = onAnnotateCell
        context.coordinator.onEditAnnotation = onEditAnnotation
        context.coordinator.onDeleteAnnotation = onDeleteAnnotation

        let currentIDs = annotations.map(\.id)
        let htmlChanged = html != context.coordinator.lastHTML
        let annotationsChanged = currentIDs != context.coordinator.lastAnnotationIDs
        let colorChanged = highlightColorR != context.coordinator.lastHighlightR
                        || highlightColorG != context.coordinator.lastHighlightG
                        || highlightColorB != context.coordinator.lastHighlightB

        if htmlChanged {
            context.coordinator.lastHTML = html
            context.coordinator.pageLoaded = false
            webView.loadHTMLString(wrapInHTMLDocument(html), baseURL: nil)
        } else if (annotationsChanged || colorChanged) && context.coordinator.pageLoaded {
            context.coordinator.lastAnnotationIDs = currentIDs
            context.coordinator.lastHighlightR = highlightColorR
            context.coordinator.lastHighlightG = highlightColorG
            context.coordinator.lastHighlightB = highlightColorB
            context.coordinator.injectHighlights(into: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func wrapInHTMLDocument(_ tableHTML: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, system-ui;
                font-size: 14px;
                color: var(--text);
                background: transparent;
                -webkit-text-size-adjust: none;
            }
            @media (prefers-color-scheme: dark) {
                :root {
                    --text: #f5f5f7;
                    --border: #545458;
                    --header-bg: #3a3a3c;
                    --row-alt: #1c1c1e;
                }
            }
            @media (prefers-color-scheme: light) {
                :root {
                    --text: #1d1d1f;
                    --border: #d2d2d7;
                    --header-bg: #f5f5f7;
                    --row-alt: #fafafa;
                }
            }
            table { border-collapse: separate; border-spacing: 0; width: 100%; min-width: fit-content; }
            th, td { border: 1px solid var(--border); padding: 8px 10px; text-align: left; white-space: nowrap; }
            th { background-color: var(--header-bg); font-weight: 600; font-size: 13px; position: sticky; top: 0; z-index: 1; border-bottom: 2px solid var(--border); will-change: transform; }
            tr:nth-child(even) td { background: var(--row-alt); }
        </style>
        </head>
        <body>
        \(tableHTML)
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var lastHTML: String = ""
        var lastAnnotationIDs: [UUID] = []
        var lastHighlightR: Double = 1.0
        var lastHighlightG: Double = 0.93
        var lastHighlightB: Double = 0.27
        var annotations: [Annotation] = []
        var highlightColorR: Double = 1.0
        var highlightColorG: Double = 0.93
        var highlightColorB: Double = 0.27
        var pageLoaded = false
        var onScrollBegan: () -> Void = {}
        var onScrollEnded: () -> Void = {}
        var onAnnotateCell: ((Int, Int) -> Void)?
        var onEditAnnotation: ((Annotation) -> Void)?
        var onDeleteAnnotation: ((Annotation) -> Void)?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            lastAnnotationIDs = annotations.map(\.id)
            injectHighlights(into: webView)
        }

        func injectHighlights(into webView: WKWebView) {
            let r = Int(highlightColorR * 255)
            let g = Int(highlightColorG * 255)
            let b = Int(highlightColorB * 255)

            var script = "document.querySelectorAll('td, th').forEach(function(cell) { cell.style.removeProperty('background-color'); });"

            for annotation in annotations where annotation.isCellAnnotation {
                let row = annotation.cellRow
                let col = annotation.cellColumn
                script += """
                (function() {
                    var rows = document.querySelectorAll('tr');
                    if (rows[\(row)]) {
                        var cells = rows[\(row)].querySelectorAll('td, th');
                        if (cells[\(col)]) {
                            cells[\(col)].style.backgroundColor = 'rgba(\(r), \(g), \(b), 0.45)';
                        }
                    }
                })();
                """
            }

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let webView = gesture.view as? WKWebView else { return }

            let point = gesture.location(in: webView)
            let script = """
            (function() {
                var el = document.elementFromPoint(\(point.x), \(point.y));
                while (el && el.tagName !== 'TD' && el.tagName !== 'TH') {
                    el = el.parentElement;
                }
                if (!el) return null;
                var row = el.parentElement ? el.parentElement.rowIndex : -1;
                var col = el.cellIndex;
                var text = el.textContent ? el.textContent.trim() : '';
                return JSON.stringify({row: row, col: col, text: text});
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self = self,
                      let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let row = dict["row"] as? Int,
                      let col = dict["col"] as? Int,
                      row >= 0, col >= 0 else { return }

                DispatchQueue.main.async {
                    if let existing = self.annotations.first(where: { $0.isCellAnnotation && $0.cellRow == row && $0.cellColumn == col }) {
                        self.onEditAnnotation?(existing)
                    } else {
                        self.onAnnotateCell?(row, col)
                    }
                }
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onScrollBegan()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { onScrollEnded() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            onScrollEnded()
        }
    }
}
