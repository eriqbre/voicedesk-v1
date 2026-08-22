import SwiftUI
import WebKit
import VoiceDeskLogic

/// Mail-like body pane. HTML uses a sandboxed WKWebView; links open in Safari on tap.
struct EmailBodyReader: View {
    let html: String?
    let plain: String?

    var body: some View {
        Group {
            if let html, EmailBodyFormatting.looksLikeHTML(html) {
                EmailHTMLView(html: html)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 360, alignment: .top)
            } else if let plain, !plain.isEmpty {
                ScrollView {
                    Text(plain)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
            }
        }
    }
}

struct EmailHTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.allowsInlineMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = Self.wrappedDocument(html)
        guard context.coordinator.loadedHTML != document else { return }
        context.coordinator.loadedHTML = document
        webView.loadHTMLString(document, baseURL: nil)
    }

    static func wrappedDocument(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        body { margin: 0; padding: 0; font: -apple-system-body; color: #1c1c1e; line-height: 1.45; word-wrap: break-word; }
        img, table { max-width: 100%; }
        img { height: auto; }
        a { color: #0b57d0; }
        </style>
        </head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }
    }
}
