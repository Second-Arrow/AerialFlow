import Foundation

/// Applies time- and brightness-based filtering for picking the next Aerial.
struct LightSensitiveAssetFilter: Sendable {
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    func isWithinAllowedLightWindow(startMinutes: Int, endMinutes: Int) -> Bool {
        let minutes = minutesSinceMidnight(now: now(), calendar: calendar)
        let start = min(24 * 60, max(0, startMinutes))
        let end = min(24 * 60, max(0, endMinutes))
        if start <= end {
            return (start...end).contains(minutes)
        } else {
            // If the window crosses midnight, treat it as two intervals.
            return minutes >= start || minutes <= end
        }
    }

    func filterIfNeeded(
        assets: [AerialAsset],
        settings: any AerialEngineSettings,
        brightnessStore: any AerialBrightnessStoring
    ) async -> [AerialAsset] {
        guard settings.isLightSensitiveFilteringEnabled else { return assets }

        // If light is allowed right now, don't restrict.
        if isWithinAllowedLightWindow(startMinutes: settings.allowedLightStartMinutes, endMinutes: settings.allowedLightEndMinutes) {
            return assets
        }

        let threshold = min(1.0, max(0.0, settings.lightSensitivity))
        var dark: [AerialAsset] = []
        dark.reserveCapacity(min(assets.count, 32))
        for asset in assets {
            if Task.isCancelled { break }
            guard !asset.id.isEmpty else { continue }
            if await brightnessStore.isDark(assetID: asset.id, threshold: threshold) == true {
                dark.append(asset)
            }
        }

        // If brightness is unknown (cache empty) or no assets are dark enough, fall back to unfiltered list.
        return dark.isEmpty ? assets : dark
    }

    private func minutesSinceMidnight(now: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return min(24 * 60, max(0, (h * 60) + m))
    }
}


