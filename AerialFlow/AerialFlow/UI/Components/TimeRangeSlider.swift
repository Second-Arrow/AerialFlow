import SwiftUI

/// A dual-thumb slider for selecting a time range expressed as minutes since midnight.
struct TimeRangeSlider: View {
    let title: String
    @Binding var startMinutes: Int
    @Binding var endMinutes: Int

    var range: ClosedRange<Int> = 0...(24 * 60)
    var step: Int = 5

    private enum ActiveThumb: Sendable { case start, end }
    @State private var activeThumb: ActiveThumb?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(TimeOfDayFormatter.string(minutes: startMinutes)) – \(TimeOfDayFormatter.string(minutes: endMinutes))")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let trackHeight: CGFloat = 6
                let thumbSize: CGFloat = 16

                let lower = CGFloat(startMinutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
                let upper = CGFloat(endMinutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)

                let startX = lower * w
                let endX = upper * w

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: trackHeight)
                        .position(x: w / 2, y: h / 2)

                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(height: trackHeight)
                        .position(x: (startX + endX) / 2, y: h / 2)
                        .frame(width: max(0, endX - startX))

                    thumb(x: startX, size: thumbSize)
                        .highPriorityGesture(dragGesture(width: w, thumb: .start))

                    thumb(x: endX, size: thumbSize)
                        .highPriorityGesture(dragGesture(width: w, thumb: .end))
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: w, thumb: nil))
            }
            .frame(height: 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(TimeOfDayFormatter.string(minutes: startMinutes)) to \(TimeOfDayFormatter.string(minutes: endMinutes))"))
        }
        .onAppear { normalize() }
        .onChange(of: startMinutes) { _, _ in normalize() }
        .onChange(of: endMinutes) { _, _ in normalize() }
    }

    private func normalize() {
        startMinutes = clampAndSnap(startMinutes)
        endMinutes = clampAndSnap(endMinutes)
        if startMinutes > endMinutes {
            swap(&startMinutes, &endMinutes)
        }
    }

    private func clampAndSnap(_ value: Int) -> Int {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard step > 1 else { return clamped }
        let snapped = Int((Double(clamped) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    private func thumb(x: CGFloat, size: CGFloat) -> some View {
        Circle()
            .fill(Color(NSColor.windowBackgroundColor))
            .overlay(
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 1, y: 1)
            .frame(width: size, height: size)
            .position(x: x, y: 14)
    }

    private func dragGesture(width: CGFloat, thumb: ActiveThumb?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeThumb == nil {
                    if let thumb {
                        activeThumb = thumb
                    } else {
                        // Pick closest thumb on first drag.
                        let startX = position(for: startMinutes, width: width)
                        let endX = position(for: endMinutes, width: width)
                        let dxStart = abs(value.location.x - startX)
                        let dxEnd = abs(value.location.x - endX)
                        activeThumb = dxStart <= dxEnd ? .start : .end
                    }
                }

                let minutes = minutesForPosition(value.location.x, width: width)
                switch activeThumb {
                case .start:
                    startMinutes = min(minutes, endMinutes)
                case .end:
                    endMinutes = max(minutes, startMinutes)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeThumb = nil
            }
    }

    private func minutesForPosition(_ x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return startMinutes }
        let t = min(1, max(0, x / width))
        let raw = Double(range.lowerBound) + (Double(range.upperBound - range.lowerBound) * Double(t))
        return clampAndSnap(Int(raw.rounded()))
    }

    private func position(for minutes: Int, width: CGFloat) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let t = CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
        return t * width
    }
}

enum TimeOfDayFormatter {
    static func string(minutes: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let clamped = min(24 * 60, max(0, minutes))
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = clamped / 60
        comps.minute = clamped % 60
        comps.second = 0
        let date = calendar.date(from: comps) ?? Date()

        let usesAMPM = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? true
        let template = usesAMPM ? "jm" : "Hm"

        let df = DateFormatter()
        df.locale = locale
        df.setLocalizedDateFormatFromTemplate(template)
        return df.string(from: date)
    }
}


