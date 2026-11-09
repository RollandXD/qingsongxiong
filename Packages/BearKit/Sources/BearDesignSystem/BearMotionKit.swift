import SwiftUI

/// 动效参数集：所有页面与组件只从这里取曲线，便于统一调手感。
public extension BearMotion {
    /// 入场错峰间隔（秒）。
    static let stagger: Double = 0.04
    /// 展开时窗口行错峰（秒）。
    static let rowStagger: Double = 0.03
    static let entrance = Animation.spring(duration: 0.62, bounce: 0.12)
    static let press = Animation.spring(duration: 0.22, bounce: 0.3)
    static let alert = Animation.spring(duration: 0.3, bounce: 0.5)

    /// Reduce Motion 下统一降级为淡入淡出。
    static func choose(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? quiet : animation
    }
}

/// 可动画环形弧：`progress` 参与插值，避免 GeometryReader 逐帧重排。
public struct BearRingShape: Shape {
    public var progress: Double
    public var span: Double
    public init(progress: Double, span: Double = 0.75) {
        self.progress = min(1, max(0, progress)); self.span = span
    }
    public var animatableData: Double {
        get { progress }
        set { progress = min(1, max(0, newValue)) }
    }
    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(90 + (1 - span) * 180)
        let end = Angle.degrees(start.degrees + 360 * span * progress)
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
            startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

/// 一圈额度环（轨道 + 进度），线宽随尺寸缩放。
public struct BearRing: View {
    let fraction: Double
    let color: Color
    let stale: Bool
    let lineWidth: CGFloat
    let trackColor: Color?
    @Environment(\.colorScheme) private var scheme
    public init(fraction: Double, color: Color, stale: Bool = false, lineWidth: CGFloat = 8, trackColor: Color? = nil) {
        self.fraction = min(1, max(0, fraction)); self.color = color; self.stale = stale
        self.lineWidth = lineWidth; self.trackColor = trackColor
    }
    public var body: some View {
        ZStack {
            BearRingShape(progress: 1)
                .stroke(trackColor ?? BearTheme.track(scheme), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            BearRingShape(progress: fraction)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: stale ? [4, 4] : []))
        }
            .padding(lineWidth / 2)
            .accessibilityHidden(true)
    }
}

/// 三家同心「额度星环」，外到内按输入顺序。
public struct BearOrbit: View {
    public struct Lane: Identifiable, Equatable {
        public let id: String
        public let fraction: Double
        public let color: Color
        public let stale: Bool
        public init(id: String, fraction: Double, color: Color, stale: Bool) {
            self.id = id; self.fraction = fraction; self.color = color; self.stale = stale
        }
    }
    let lanes: [Lane]
    let lineWidth: CGFloat
    let gap: CGFloat
    public init(lanes: [Lane], lineWidth: CGFloat = 9, gap: CGFloat = 5) {
        self.lanes = lanes; self.lineWidth = lineWidth; self.gap = gap
    }
    public var body: some View {
        ZStack {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                BearRing(fraction: lane.fraction, color: lane.color, stale: lane.stale, lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + gap))
            }
        }.accessibilityHidden(true)
    }
}

/// 带刻度的容量胶囊：每 25% 一道刻度，可选重置时刻点。
public struct BearTickCapsule: View {
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
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor ?? BearTheme.track(scheme))
                Capsule().fill(color.gradient).frame(width: max(geometry.size.height, width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                ForEach(1..<4, id: \.self) { tick in
                    Rectangle().fill(BearTheme.background(scheme).opacity(0.55))
                        .frame(width: 1.5).offset(x: width * CGFloat(tick) / 4)
                }
            }
                .clipShape(Capsule())
                .overlay {
                if stale { Capsule().strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
        }.frame(height: 10).accessibilityHidden(true)
    }
}

/// 熊的情绪，由最低剩余量与连接状态决定（判定在展示层，这里只管画）。
public enum BearMood: String, CaseIterable, Sendable {
    case calm, watchful, urgent, asleep
}

/// 带情绪的轻松熊：仅在 mood 变化时播放一次关键帧，静止时零动画。
public struct BearMoodMark: View {
    let mood: BearMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0
    public init(mood: BearMood) { self.mood = mood }
    private struct Pose { var tilt = 0.0; var scale = 1.0; var blink = 1.0; var lift = 0.0 }
    public var body: some View {
        BearFace(mood: mood)
            .keyframeAnimator(initialValue: Pose(), trigger: trigger) { content, pose in
            content
                .rotationEffect(.degrees(pose.tilt))
                .scaleEffect(x: pose.scale, y: pose.scale * pose.blink)
                .offset(y: pose.lift)
        } keyframes: { _ in
            // 关键帧轨道内不用分支，按情绪算幅度，保证编译器稳定推断。
            let tilt = mood == .watchful ? -9.0 : mood == .urgent ? -6.0 : 0
            let wobble = mood == .urgent ? 6.0 : 0
            let blink = mood == .calm ? 0.15 : 1
            let lift = mood == .asleep ? 2.0 : -3
            KeyframeTrack(\.tilt) {
                CubicKeyframe(tilt, duration: 0.1)
                CubicKeyframe(wobble, duration: 0.1)
                SpringKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.blink) {
                LinearKeyframe(1, duration: 0.1)
                CubicKeyframe(blink, duration: 0.08)
                CubicKeyframe(1, duration: 0.12)
            }
            KeyframeTrack(\.scale) {
                SpringKeyframe(mood == .asleep ? 0.96 : 1.06, duration: 0.18)
                SpringKeyframe(1, duration: 0.35)
            }
            KeyframeTrack(\.lift) {
                SpringKeyframe(lift, duration: 0.2)
                SpringKeyframe(0, duration: 0.35)
            }
        }
            .onChange(of: mood) { _, _ in if !reduceMotion { trigger &+= 1 } }
            .accessibilityHidden(true)
    }
}

private struct BearFace: View {
    let mood: BearMood
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ink = Color(red: 0.18, green: 0.12, blue: 0.08)
            ZStack {
                BearMark()
                switch mood {
                    case .asleep:
                    HStack(spacing: side * 0.2) {
                        Capsule().frame(width: side * 0.1, height: side * 0.02)
                        Capsule().frame(width: side * 0.1, height: side * 0.02)
                    }.foregroundStyle(ink).offset(y: -side * 0.025)
                        .background(Ellipse().fill(BearTheme.caramel).frame(width: side * 0.5, height: side * 0.09).offset(y: -side * 0.025))
                    Text("z").font(.system(size: side * 0.2, weight: .bold, design: .rounded))
                        .foregroundStyle(BearTheme.secondaryText(scheme)).offset(x: side * 0.45, y: -side * 0.42)
                    case .urgent:
                    Circle().fill(Color(red: 0.55, green: 0.75, blue: 0.95)).frame(width: side * 0.08, height: side * 0.11)
                        .offset(x: side * 0.33, y: -side * 0.05)
                    case .watchful, .calm: EmptyView()
                }
            }.frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 玻璃卡容器：系列色极淡网格渐变 + 细描边；iOS 27 使用 Liquid Glass。
public struct BearGlassCard: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    public func body(content: Content) -> some View {
        content
            .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(BearTheme.surface(scheme).opacity(scheme == .dark ? 0.55 : 0.72))
                .overlay {
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                    colors: BearTheme.meshStops(tint: tint, scheme))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
                // 材质仅作用于背景，不让系统 vibrancy 降低正文的实际对比度。
                .glassEffect(.regular.tint(tint.opacity(scheme == .dark ? 0.08 : 0.04)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
            .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(BearTheme.text(scheme).opacity(scheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
        }
    }
}

public extension View {
    func bearGlassCard(tint: Color, cornerRadius: CGFloat = 26) -> some View {
        modifier(BearGlassCard(tint: tint, cornerRadius: cornerRadius))
    }
}

/// 卡片按压：缩放 + 高光跟随按压位置。
public struct BearLiftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.015 : 0)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.press, value: configuration.isPressed)
    }
}
