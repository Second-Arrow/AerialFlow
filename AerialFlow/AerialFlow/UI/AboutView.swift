import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    @State private var isShowingLicense: Bool = false
    @State private var isShowingAcknowledgments: Bool = false

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            AboutWindowContentView(
                isShowingLicense: $isShowingLicense,
                isShowingAcknowledgments: $isShowingAcknowledgments,
                onDonate: {
                    guard let url = Constants.supportURL else { return }
                    openURL(url)
                }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .sheet(isPresented: $isShowingLicense) {
            TextDocumentSheet(
                title: "License",
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


