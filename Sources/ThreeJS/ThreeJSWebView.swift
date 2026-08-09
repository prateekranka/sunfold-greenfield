import SwiftUI
import UIKit
import WebKit

struct ThreeJSWebView: UIViewRepresentable {
    @ObservedObject var bridge: ThreeJSBridge

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(bridge, name: "sunfold")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.isInspectable = false
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        bridge.attach(to: webView)

        // Xcode copies the contents of the checked-in Resources/ThreeRuntime
        // directory into the app bundle root. Keep source and bundle layout
        // independent so the same HTML works in Debug and Release packaging.
        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            bridge.reportLocalFailure("The bundled Three.js index.html is missing.")
            return webView
        }
        context.coordinator.allowedBundleURL = Bundle.main.bundleURL
        webView.loadFileURL(indexURL, allowingReadAccessTo: Bundle.main.bundleURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var bridge: ThreeJSBridge?
        var allowedBundleURL: URL?

        init(bridge: ThreeJSBridge) {
            self.bridge = bridge
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url,
                  let allowedBundleURL,
                  url.isFileURL,
                  isWithinBundle(url, bundleURL: allowedBundleURL)
            else {
                bridge?.reportLocalFailure("The runtime blocked a non-local navigation request.")
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            guard let url = navigationResponse.response.url,
                  let allowedBundleURL,
                  url.isFileURL,
                  isWithinBundle(url, bundleURL: allowedBundleURL)
            else {
                bridge?.reportLocalFailure("The runtime blocked a non-local navigation response.")
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // The bridge owns the user-facing failure. Keep the web view local and
            // avoid showing a WebKit error page or any remote fallback.
            webView.isHidden = true
        }

        private func isWithinBundle(_ url: URL, bundleURL: URL) -> Bool {
            let bundlePath = bundleURL.standardizedFileURL.path
            let candidatePath = url.standardizedFileURL.path
            return candidatePath == bundlePath || candidatePath.hasPrefix(bundlePath + "/")
        }
    }
}
