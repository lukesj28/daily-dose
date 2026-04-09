import SwiftUI
import WebKit

struct MathBlockView: View {
    let mathml: String
    @State private var contentHeight: CGFloat = 60

    var body: some View {
        MathWebView(mathml: mathml) { height in
            contentHeight = height
        }
        .frame(height: contentHeight)
        .padding(.vertical, 4)
    }
}

private struct MathWebView: UIViewRepresentable {
    let mathml: String
    let onHeightMeasured: (CGFloat) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeightMeasured = onHeightMeasured
        guard mathml != context.coordinator.lastMathml else { return }
        context.coordinator.lastMathml = mathml
        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func buildHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, system-ui;
                font-size: 16px;
                background: transparent;
                display: flex;
                justify-content: center;
                padding: 4px 0;
                overflow: hidden;
                -webkit-text-size-adjust: none;
            }
            @media (prefers-color-scheme: dark) { body { color: #f5f5f7; } }
            @media (prefers-color-scheme: light) { body { color: #1d1d1f; } }
            math { display: block; }
        </style>
        </head>
        <body>\(mathml)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMathml = ""
        var onHeightMeasured: ((CGFloat) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                let height = (result as? Double).map { CGFloat($0) } ?? 60
                self.onHeightMeasured?(height)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }
}
