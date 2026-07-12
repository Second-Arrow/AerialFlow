import Foundation
import os

/// Presentation-oriented helpers for turning catalog data into UI-friendly strings/structures.
///
/// This keeps UI formatting/name resolution out of `AppState`, while remaining pure and testable:
/// - Reads catalog snapshots via `AerialCataloging`
/// - Resolves localized strings via `CategoryResolver`
struct CatalogPresentationService: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "CatalogPresentationService")

    private let catalog: any AerialCataloging
    private let resolver: CategoryResolver

    init(catalog: any AerialCataloging, resolver: CategoryResolver) {
        self.catalog = catalog
        self.resolver = resolver
    }

    func categoryDisplayNamesByID(categories: [AerialCategory]) async -> [String: String] {
        let idToNames = await resolver.categoryIDToNames(categories: categories)
        var out: [String: String] = [:]
        out.reserveCapacity(categories.count)

        for category in categories {
            guard !category.id.isEmpty else { continue }
            let names = idToNames[category.id] ?? []
            let best = names
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .first
            out[category.id] = best ?? category.id
        }

        return out
    }

    func assetDisplayNamesByID(assets: [AerialAsset]) async -> [String: String] {
        // Uses the resolver's full fallback chain
        // (localizedNameKey -> shotID -> id -> accessibilityLabel) so the Exclusions list
        // matches the names shown in the footer/menu bar.
        await resolver.assetNames(for: assets)
    }

    /// Resolves an asset ID to a human-readable display name.
    /// Returns the asset's localized name (via TVIdleScreenStrings) if available, otherwise falls back to the asset ID.
    func assetDisplayName(for assetID: String) async -> String? {
        guard !assetID.isEmpty else { return nil }

        do {
            let snapshot = try await catalog.loadSnapshot()
            if let asset = snapshot.assets.first(where: { $0.id == assetID }) {
                return await resolver.assetName(for: asset) ?? assetID
            }
            return await resolver.assetName(for: assetID) ?? assetID
        } catch {
            logger.debug("Failed to resolve asset display name for \(assetID, privacy: .public): \(String(describing: error), privacy: .public)")
            return assetID
        }
    }

    /// Returns the subcategory IDs of the asset, or `[]` when the asset can't be resolved.
    func subcategoryIDs(for assetID: String?) async -> Set<String> {
        guard let assetID, !assetID.isEmpty else { return [] }

        do {
            let snapshot = try await catalog.loadSnapshot()
            if let asset = snapshot.assets.first(where: { $0.id == assetID }) {
                return Set(asset.subcategories)
            }
            return []
        } catch {
            logger.debug("Failed to load catalog for subcategory IDs: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}

