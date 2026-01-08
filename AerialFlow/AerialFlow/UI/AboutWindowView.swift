import AppKit
import SwiftUI

struct AboutWindowView: View {
    @Environment(\.openURL) private var openURL

    @State private var isShowingLicense: Bool = false
    @State private var isShowingAcknowledgments: Bool = false

    var body: some View {
        AboutWindowContentView(
            isShowingLicense: $isShowingLicense,
            isShowingAcknowledgments: $isShowingAcknowledgments,
            onDonate: {
                guard let url = Constants.supportURL else { return }
                openURL(url)
            }
        )
        .padding(24)
        .frame(width: 640, height: 320)
        .sheet(isPresented: $isShowingLicense) {
            TextDocumentSheet(
                title: "MIT License",
                text: BundledText.loadLicenseText()
            )
        }
        .sheet(isPresented: $isShowingAcknowledgments) {
            TextDocumentSheet(
                title: "Acknowledgments",
                text: BundledText.load("Acknowledgments", fileExtension: "txt")
            )
        }
    }
}

struct AboutWindowContentView: View {
    @Binding var isShowingLicense: Bool
    @Binding var isShowingAcknowledgments: Bool

    let onDonate: () -> Void

    private var icon: NSImage {
        NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AboutInfo.appName())
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(.primary)

                    Text(AboutInfo.versionLine())
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)

                    if let copyright = AboutInfo.copyrightLine() {
                        Text(copyright)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("MIT License") { isShowingLicense = true }
                Button("Acknowledgments") { isShowingAcknowledgments = true }
                Button("Buy Me a Coffee…") { onDonate() }
            }
            .controlSize(.regular)
        }
    }
}

enum BundledText {
    static func loadLicenseText() -> String {
        load("License-Direct", fileExtension: "txt")
    }

    static func load(_ name: String, fileExtension: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return "\(name) could not be loaded. The resource is missing from the app bundle."
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "\(name) could not be loaded: \(error.localizedDescription)"
        }
    }
}


