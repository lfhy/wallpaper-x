//
//  SteamWorkshopWebView.swift
//  MyWallpaperX
//

import SwiftUI
import WebKit

struct SteamWorkshopWebView: NSViewRepresentable {
    let url: URL
    let navigationVersion: Int
    let onNavigationChanged: (URL?, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationChanged: onNavigationChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.customUserAgent = "MyWallpaperX-SteamWorkshop/1.0"
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let currentURL = nsView.url?.absoluteString
        if currentURL != url.absoluteString || context.coordinator.lastNavigationVersion != navigationVersion {
            context.coordinator.lastNavigationVersion = navigationVersion
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigationChanged: (URL?, String?) -> Void
        var lastNavigationVersion = 0

        init(onNavigationChanged: @escaping (URL?, String?) -> Void) {
            self.onNavigationChanged = onNavigationChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationChanged(webView.url, webView.title)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onNavigationChanged(webView.url, webView.title)
        }
    }
}
