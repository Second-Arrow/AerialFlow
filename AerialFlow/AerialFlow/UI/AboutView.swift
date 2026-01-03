import SwiftUI

struct AboutView: View {
    private let websiteURL = URL(string: "https://secondarrow.io/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("About AerialFlow")
                    .font(.headline)
                Text(versionLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("AerialFlow fixes the macOS Aerials rotation bug and keeps your wallpapers switching smoothly in the background.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Made with love")
                    .font(.headline)
                Text("AerialFlow is a free app created with care for people who love beautiful macOS backgrounds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Second Arrow")
                    .font(.headline)
                Link("secondarrow.io", destination: websiteURL)
                    .font(.footnote)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Support Development")
                    .font(.headline)
                Text("If you’d like to support ongoing maintenance and improvements, you can leave an optional tip via “Support Development…” below. Tips don’t unlock features.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (v, b) {
        case (let v?, let b?):
            return "Version \(v) (\(b))"
        case (let v?, nil):
            return "Version \(v)"
        case (nil, let b?):
            return "Build \(b)"
        default:
            return "Version —"
        }
    }
}


