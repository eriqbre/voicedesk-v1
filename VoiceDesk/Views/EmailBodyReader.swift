import SwiftUI
import WebKit
import VoiceDeskLogic

/// Mail-like body pane. Latest message grows with content; history can stay capped.
struct EmailBodyReader: View {
    let html: String?
    let plain: String?
    var expandsToFit: Bool = true

    var body: some View {
        Group {
            if let html, EmailBodyFormatting.looksLikeHTML(html) {
                EmailHTMLView(html: html, expandsToFit: expandsToFit)
            } else if let plain, !plain.isEmpty {
                Text(plain)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct EmailHTMLView: View {
    @Environment(AppModel.self) private var model
    let html: String
    var expandsToFit: Bool = true
    @State private var measuredHeight: CGFloat = 160

    /// Pathological HTML only. Latest messages should fit well under this.
    private static let latestCap: CGFloat = 4000
    private static let historyCap: CGFloat = 520

    var body: some View {
        let cap = expandsToFit ? Self.latestCap : Self.historyCap
        let height = min(max(measuredHeight, 120), cap)
        EmailHTMLWebView(html: html, measuredHeight: $measuredHeight, scrollingEnabled: !expandsToFit || measuredHeight > cap)
            .frame(maxWidth: .infinity, minHeight: height, idealHeight: height, maxHeight: height, alignment: .top)
            .onChange(of: measuredHeight) { previous, next in
                guard expandsToFit, next > previous + 40 else { return }
                model.noteVisibleCardGrew()
            }
    }
}

private struct EmailHTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat
    var scrollingEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = scrollingEnabled
        webView.setContentHuggingPriority(.required, for: .vertical)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.scrollView.isScrollEnabled = scrollingEnabled
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
        html, body { margin: 0; padding: 0; font: -apple-system-body; color: #1c1c1e; line-height: 1.45; word-wrap: break-word; }
        img, table { max-width: 100%; }
        img { height: auto; }
        a { color: #0b57d0; }
        </style>
        </head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var measuredHeight: Binding<CGFloat>

        init(measuredHeight: Binding<CGFloat>) {
            self.measuredHeight = measuredHeight
        }

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight)"
            webView.evaluateJavaScript(script) { result, _ in
                let value: CGFloat
                if let number = result as? Double {
                    value = CGFloat(number)
                } else if let number = result as? CGFloat {
                    value = number
                } else {
                    value = webView.scrollView.contentSize.height
                }
                DispatchQueue.main.async {
                    self.measuredHeight.wrappedValue = max(120, value)
                }
            }
        }
    }
}
