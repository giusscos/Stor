import SwiftUI
import WebKit

/// Signs the user into Apple Ads Advanced in a WebView, then exports session cookies
/// needed for unofficial CM keyword popularity / recommendation APIs.
struct AppleAdsLoginView: View {
    let onSave: (AppleAdsWebSession) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var statusMessage = "Sign in with your Apple ID, then click Save Session."

    private let webStore = AppleAdsWebViewStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banner
                Divider()
                AppleAdsWKWebView(store: webStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Sign in to Apple Ads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await captureSession() }
                    } label: {
                        if isCapturing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save Session")
                        }
                    }
                    .disabled(isCapturing)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Couldn’t Save Session", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 560, idealHeight: 640)
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusMessage)
                .font(.callout)
            Text("Popularity scores come from the Apple Ads dashboard session (same data Astro uses), not from the API key alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.blue.opacity(0.06))
    }

    @MainActor
    private func captureSession() async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let session = try await webStore.exportSession()
            guard !session.isEmpty else {
                errorMessage = "No Apple Ads cookies found. Finish signing in, open Campaigns once, then try again."
                return
            }
            try KeychainService.shared.saveAppleAdsWebSession(session)
            statusMessage = "Session saved."
            onSave(session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WebView bridge

@MainActor
final class AppleAdsWebViewStore {
    weak var webView: WKWebView?

    func exportSession() async throws -> AppleAdsWebSession {
        guard let webView else {
            throw AppleAdsWebError.notReady
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }

        let relevant = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("apple.com")
                || domain.contains("app-ads.apple.com")
                || domain.contains("idmsa.apple.com")
                || domain.contains("searchads.apple.com")
        }

        guard !relevant.isEmpty else {
            return AppleAdsWebSession(cookieHeader: "", xsrfToken: nil, savedAt: .now)
        }

        let cookieHeader = HTTPCookie.requestHeaderFields(with: relevant)["Cookie"] ?? ""
        let xsrf = relevant
            .first { $0.name.caseInsensitiveCompare("XSRF-TOKEN-CM") == .orderedSame }
            .map(\.value)
            .flatMap { $0.removingPercentEncoding ?? $0 }

        return AppleAdsWebSession(
            cookieHeader: cookieHeader,
            xsrfToken: xsrf,
            savedAt: .now
        )
    }
}

private struct AppleAdsWKWebView: NSViewRepresentable {
    let store: AppleAdsWebViewStore

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        store.webView = webView
        if let url = URL(string: "https://app-ads.apple.com") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        store.webView = nsView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {}
}

enum AppleAdsWebError: LocalizedError {
    case notReady
    case noSession
    case sessionExpired
    case httpError(Int, String)
    case ownedAppRequired
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Apple Ads login view is not ready yet."
        case .noSession:
            return "Sign in to Apple Ads to fetch keyword popularity."
        case .sessionExpired:
            return "Apple Ads session expired. Sign in again."
        case .httpError(let code, let body):
            return "Apple Ads HTTP \(code): \(body.prefix(280))"
        case .ownedAppRequired:
            return "This app isn’t available in your Apple Ads account. Link App Store Connect in Ads, or use an owned app."
        case .decodeFailed:
            return "Unexpected Apple Ads response."
        }
    }
}
