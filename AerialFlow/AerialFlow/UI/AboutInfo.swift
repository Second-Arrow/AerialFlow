import Foundation

enum AboutInfo {
    static func appName(bundle: Bundle = .main) -> String {
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "AerialFlow"
    }

    static func versionLine(bundle: Bundle = .main) -> String {
        let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let b = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return versionLine(shortVersion: v, build: b)
    }

    static func versionLine(shortVersion: String?, build: String?) -> String {
        switch (shortVersion?.nonEmptyTrimmed, build?.nonEmptyTrimmed) {
        case (let v?, let b?):
            return "Version \(v) (Build \(b))"
        case (let v?, nil):
            return "Version \(v)"
        case (nil, let b?):
            return "Build \(b)"
        default:
            return "Version —"
        }
    }

    static func copyrightLine(bundle: Bundle = .main) -> String? {
        if let s = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           let trimmed = s.nonEmptyTrimmed {
            return trimmed
        }
        // Project currently sets this key to "", so fall back to a stable string.
        return "Copyright © 2026 Second Arrow"
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


