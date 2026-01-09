import Foundation

/// Editing helpers for the embedded `Configuration` plist blobs stored in provider nodes.
struct WallpaperStoreConfigurationPlist: Sendable {
    private let configDecodeFailed: @Sendable (_ underlying: Error) -> Error
    private let configEncodeFailed: @Sendable (_ underlying: Error) -> Error

    init(
        configDecodeFailed: @escaping @Sendable (_ underlying: Error) -> Error,
        configEncodeFailed: @escaping @Sendable (_ underlying: Error) -> Error
    ) {
        self.configDecodeFailed = configDecodeFailed
        self.configEncodeFailed = configEncodeFailed
    }

    func rewriteConfiguration(_ data: Data, assetID: String) throws -> Data {
        let cfgAny: Any
        do {
            cfgAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw configDecodeFailed(error)
        }

        guard var cfg = cfgAny as? [String: Any] else {
            throw configDecodeFailed(
                NSError(
                    domain: "AerialFlow.WallpaperStoreConfigurationPlist",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Embedded Configuration plist was not a dictionary."]
                )
            )
        }
        cfg["assetID"] = assetID

        do {
            return try PropertyListSerialization.data(fromPropertyList: cfg, format: .binary, options: 0)
        } catch {
            throw configEncodeFailed(error)
        }
    }

    func makeConfigurationData(assetID: String) throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        } catch {
            throw configEncodeFailed(error)
        }
    }
}

