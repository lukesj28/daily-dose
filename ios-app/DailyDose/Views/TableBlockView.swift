import SwiftUI
import WebKit

struct TableBlockView: UIViewRepresentable {
    let html: String
    var annotations: [Annotation] = []
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

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        webView.addGestureRecognizer(longPress)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.annotations = annotations
        context.coordinator.onAnnotateCell = onAnnotateCell
        context.coordinator.onEditAnnotation = onEditAnnotation
        context.coordinator.onDeleteAnnotation = onDeleteAnnotation
        webView.accessibilityCustomActions = context.coordinator.accessibilityActions(for: webView)

        let highlightKeys = annotations.map(\.highlightKey)
        let htmlChanged = html != context.coordinator.lastHTML
        let annotationsChanged = highlightKeys != context.coordinator.lastHighlightKeys

        if htmlChanged {
            context.coordinator.lastHTML = html
            context.coordinator.pageLoaded = false
            webView.loadHTMLString(wrapInHTMLDocument(html), baseURL: nil)
        } else if annotationsChanged && context.coordinator.pageLoaded {
            context.coordinator.lastHighlightKeys = highlightKeys
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
                font: -apple-system-subheadline;
                color: var(--text);
                background: transparent;
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
            th { background-color: var(--header-bg); font: -apple-system-footnote; font-weight: 600; position: sticky; top: 0; z-index: 1; border-bottom: 2px solid var(--border); will-change: transform; }
            tr:nth-child(even) td { background: var(--row-alt); }
            \(HighlightColor.stylesheet)
        </style>
        </head>
        <body>
        \(tableHTML)
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var lastHighlightKeys: [HighlightKey] = []
        var annotations: [Annotation] = []
        var pageLoaded = false
        var onAnnotateCell: ((Int, Int) -> Void)?
        var onEditAnnotation: ((Annotation) -> Void)?
        var onDeleteAnnotation: ((Annotation) -> Void)?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            lastHighlightKeys = annotations.map(\.highlightKey)
            injectHighlights(into: webView)
        }

        func injectHighlights(into webView: WKWebView) {
            var script = "document.querySelectorAll('[data-hl]').forEach(function(cell) { cell.removeAttribute('data-hl'); });"

            for annotation in annotations where annotation.isCellAnnotation {
                let row = annotation.cellRow
                let col = annotation.cellColumn
                script += """
                (function() {
                    var rows = document.querySelectorAll('tr');
                    if (rows[\(row)]) {
                        var cells = rows[\(row)].querySelectorAll('td, th');
                        if (cells[\(col)]) {
                            cells[\(col)].setAttribute('data-hl', '\(annotation.highlightColor.rawValue)');
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

                DispatchQueue.main.async { self.openNote(row: row, col: col) }
            }
        }

        private func openNote(row: Int, col: Int) {
            if let existing = annotations.first(where: { $0.isCellAnnotation && $0.cellRow == row && $0.cellColumn == col }) {
                onEditAnnotation?(existing)
            } else {
                onAnnotateCell?(row, col)
            }
        }

        func accessibilityActions(for webView: WKWebView) -> [UIAccessibilityCustomAction] {
            let add = UIAccessibilityCustomAction(name: "Add Note to Cell") { [weak self, weak webView] _ in
                guard let self, let webView else { return false }
                self.promptForCell(in: webView)
                return true
            }
            let edits = annotations.filter(\.isCellAnnotation).map { note in
                UIAccessibilityCustomAction(name: "Edit Note, row \(note.cellRow + 1), column \(note.cellColumn + 1)") { [weak self] _ in
                    self?.onEditAnnotation?(note)
                    return true
                }
            }
            return [add] + edits
        }

        private func promptForCell(in webView: WKWebView) {
            guard let vc = sequence(first: webView as UIResponder, next: \.next)
                .first(where: { $0 is UIViewController }) as? UIViewController else { return }
            let alert = UIAlertController(title: "Add Note to Cell", message: "Enter the row and column numbers.", preferredStyle: .alert)
            for placeholder in ["Row", "Column"] {
                alert.addTextField {
                    $0.placeholder = placeholder
                    $0.keyboardType = .numberPad
                }
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak webView, weak alert] _ in
                guard let self, let webView,
                      let row = Int(alert?.textFields?[0].text ?? ""),
                      let col = Int(alert?.textFields?[1].text ?? ""),
                      row > 0, col > 0 else { return }
                self.addNote(row: row - 1, col: col - 1, in: webView)
            })
            (vc.presentedViewController ?? vc).present(alert, animated: true)
        }

        private func addNote(row: Int, col: Int, in webView: WKWebView) {
            let script = "(function() { var r = document.querySelectorAll('tr')[\(row)]; return !!r && !!r.querySelectorAll('td, th')[\(col)]; })()"
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                DispatchQueue.main.async {
                    if result as? Bool == true {
                        self?.openNote(row: row, col: col)
                    } else {
                        UIAccessibility.post(notification: .announcement, argument: "That cell doesn't exist")
                    }
                }
            }
        }
    }
}
