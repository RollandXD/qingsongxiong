import SwiftUI

/// 全 App 唯一的一套物理：三个弹簧 token，参数与 HTML 原型
/// （design/prototype-honey）的 response / dampingFraction 一一对应。
public enum BearMotion {
    /// 按压、切换、标尺吸附：快、几乎不过冲。
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// 布局、展开、转场：临界阻尼，不过冲。
    public static let smooth = Animation.spring(response: 0.48, dampingFraction: 1.0)
    /// 液面升降：欠阻尼，留一点晃动。
    public static let fluid = Animation.spring(response: 0.70, dampingFraction: 0.72)
    /// 与 `fluid` 同参数的解析弹簧，供需要读速度的逐帧绘制（蜜罐液面）使用。
    public static let fluidSpring = Spring(response: 0.70, dampingRatio: 0.72)
    /// Reduce Motion 下的交叉淡入。
    public static let quiet = Animation.easeOut(duration: 0.14)

    // 旧名字保留为别名，调用点逐步迁移；不再引入新的曲线。
    public static let unfold = smooth
    /// 数据刷新的整体过渡用临界阻尼，避免文字与布局跟着液面一起晃。
    public static let data = smooth
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
            .animation(BearMotion.snappy, value: configuration.isPressed)
    }
}
