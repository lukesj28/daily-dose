import SwiftUI
import WebKit

struct TableBlockView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = true
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(wrapInHTMLDocument(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func wrapInHTMLDocument(_ tableHTML: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
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
                    --border: #3a3a3c;
                    --header-bg: #2c2c2e;
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
            table { border-collapse: collapse; width: 100%; min-width: fit-content; }
            th, td { border: 1px solid var(--border); padding: 8px 10px; text-align: left; white-space: nowrap; }
            th { background: var(--header-bg); font-weight: 600; font-size: 13px; }
            tr:nth-child(even) td { background: var(--row-alt); }
        </style>
        </head>
        <body>
        \(tableHTML)
        </body>
        </html>
        """
    }

    // Block external navigation; only allow the initial HTML load
    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""

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
    }
}
