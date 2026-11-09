import SwiftUI

public enum BearMotion {
    public static let unfold = Animation.spring(duration: 0.44, bounce: 0.15)
    public static let data = Animation.spring(duration: 0.55, bounce: 0.04)
    public static let quiet = Animation.easeOut(duration: 0.14)
}

public struct BearCapacityBar: View {
    let fraction: Double
    let color: Color
    let stale: Bool
    let trackColor: Color?
    @Environment(\.colorScheme) private var scheme
    public init(fraction: Double, color: Color, stale: Bool = false, trackColor: Color? = nil) {
        self.fraction = min(1, max(0, fraction)); self.color = color; self.stale = stale; self.trackColor = trackColor
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor ?? BearTheme.track(scheme))
                Capsule().fill(color.gradient).frame(width: geometry.size.width * fraction)
            }
            .overlay {
                if stale { Capsule().strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
        }.frame(height: 8).accessibilityHidden(true)
    }
}

public struct BearQuotaArc: View {
    let fraction: Double
    let color: Color
    let stale: Bool
    let trackColor: Color?
    @Environment(\.colorScheme) private var scheme
    public init(fraction: Double, color: Color, stale: Bool = false, trackColor: Color? = nil) {
        self.fraction = min(1, max(0, fraction)); self.color = color; self.stale = stale; self.trackColor = trackColor
    }
    public var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(trackColor ?? BearTheme.track(scheme), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            Circle().trim(from: 0, to: fraction * 0.75)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: stale ? [4, 4] : []))
        }.rotationEffect(.degrees(135)).padding(5).accessibilityHidden(true)
    }
}

public struct BearCompositionBar: View {
    let fractions: [Double]
    let color: Color
    @Environment(\.colorScheme) private var scheme
    public init(fractions: [Double], color: Color) { self.fractions = fractions; self.color = color }
    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == 0 ? color : color.opacity(scheme == .dark ? 0.45 : 0.25))
                        .frame(width: max(0, geometry.size.width - CGFloat(max(0, fractions.count - 1)) * 3) * min(1, max(0, fraction)))
                }
            }
        }.frame(height: 9).accessibilityHidden(true)
    }
}

public struct BearPressStyle: ButtonStyle {
    @Environment(\.bearReduceMotion) private var reduceMotion
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
