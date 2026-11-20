import SwiftUI
import WebKit

struct MathBlockView: View {
    let mathml: String
    var annotation: Annotation? = nil
    var onAnnotate: (() -> Void)? = nil
    var onEditAnnotation: ((Annotation) -> Void)? = nil
    var onDeleteAnnotation: ((Annotation) -> Void)? = nil

    @State private var contentHeight: CGFloat = 60

    var body: some View {
        MathWebView(
            mathml: mathml,
            annotation: annotation,
            onHeightMeasured: { height in contentHeight = height },
            onAnnotate: onAnnotate,
            onEditAnnotation: onEditAnnotation,
            onDeleteAnnotation: onDeleteAnnotation
        )
        .frame(height: contentHeight)
        .padding(.vertical, 4)
    }
}

private struct MathWebView: UIViewRepresentable {
    let mathml: String
    let annotation: Annotation?
    let onHeightMeasured: (CGFloat) -> Void
    let onAnnotate: (() -> Void)?
    let onEditAnnotation: ((Annotation) -> Void)?
    let onDeleteAnnotation: ((Annotation) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
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
        context.coordinator.onHeightMeasured = onHeightMeasured
        context.coordinator.annotation = annotation
        context.coordinator.onAnnotate = onAnnotate
        context.coordinator.onEditAnnotation = onEditAnnotation
        context.coordinator.onDeleteAnnotation = onDeleteAnnotation
        webView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: annotation == nil ? "Add Note" : "Edit Note") { [coordinator = context.coordinator] _ in
                coordinator.annotateOrEdit()
                return true
            }
        ]

        let mathmlChanged = mathml != context.coordinator.lastMathml
        let annotationChanged = annotation?.highlightKey != context.coordinator.lastHighlightKey

        if mathmlChanged {
            context.coordinator.lastMathml = mathml
            context.coordinator.pageLoaded = false
            webView.loadHTMLString(buildHTML(), baseURL: nil)
        } else if annotationChanged && context.coordinator.pageLoaded {
            context.coordinator.lastHighlightKey = annotation?.highlightKey
            context.coordinator.injectHighlight(into: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func buildHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font: -apple-system-body;
                background: transparent;
                display: flex;
                justify-content: center;
                padding: 4px 0;
                overflow: hidden;
            }
            @media (prefers-color-scheme: dark) { body { color: #f5f5f7; } }
            @media (prefers-color-scheme: light) { body { color: #1d1d1f; } }
            math { display: block; }
            \(HighlightColor.stylesheet)
        </style>
        </head>
        <body>\(mathml)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMathml = ""
        var lastHighlightKey: HighlightKey?
        var annotation: Annotation?
        var pageLoaded = false
        var onHeightMeasured: ((CGFloat) -> Void)?
        var onAnnotate: (() -> Void)?
        var onEditAnnotation: ((Annotation) -> Void)?
        var onDeleteAnnotation: ((Annotation) -> Void)?

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            annotateOrEdit()
        }

        func annotateOrEdit() {
            if let existing = annotation {
                onEditAnnotation?(existing)
            } else {
                onAnnotate?()
            }
        }

        func injectHighlight(into webView: WKWebView) {
            let script = annotation.map { "document.body.setAttribute('data-hl', '\($0.highlightColor.rawValue)');" }
                ?? "document.body.removeAttribute('data-hl');"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            lastHighlightKey = annotation?.highlightKey
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                let height = (result as? Double).map { CGFloat($0) } ?? 60
                self.onHeightMeasured?(height)
            }
            injectHighlight(into: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }
}
