import SwiftUI
import AppKit
import WebKit

struct AboutView: View {
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "webiqu"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"

    private let projectWebsiteURL = URL(string: "https://webisso.github.io/webiqu-ssh-workspace/")!
    private let repositoryURL = URL(string: "https://github.com/Webisso/webiqu-ssh-workspace")!
    private let releasesURL = URL(string: "https://github.com/Webisso/webiqu-ssh-workspace/releases")!

    private var webissoLogoURL: URL? {
        Bundle.main.url(forResource: "webisso", withExtension: "svg")
            ?? Bundle.main.url(forResource: "webisso", withExtension: "svg", subdirectory: "Resources")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                Text(appName)
                    .font(.system(size: 30, weight: .semibold))
                    .textSelection(.enabled)

                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Native macOS SSH workspace for terminals, remote files, monitoring, and saved commands.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)

            Divider()
                .padding(.top, 22)

            HStack(spacing: 16) {
                aboutLink(title: "Project Website", systemImage: "safari", destination: projectWebsiteURL)
                aboutLink(title: "GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right", destination: repositoryURL)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)

            Divider()
                .padding(.top, 22)
                
            HStack {
                if let logoURL = webissoLogoURL {
                    HStack(spacing: 8) {
                        Text("Developed By")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        SVGLogoView(url: logoURL)
                            .padding(.leading, -15)
                            .frame(width: 67.2, height: 18)
                            .accessibilityLabel("Webisso")
                    }
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(releasesURL)
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Opens GitHub Releases")
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
        .frame(width: 520, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func aboutLink(title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: .labelColor))
    }
}

private struct SVGLogoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
        <style>
        html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            background: transparent;
            overflow: hidden;
        }
        .logo {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
            <img class=\"logo\" src=\"\(url.lastPathComponent)\" alt=\"Webisso\" />
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}
