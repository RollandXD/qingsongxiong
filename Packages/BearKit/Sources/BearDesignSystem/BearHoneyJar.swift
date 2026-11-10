import SwiftUI

// 蜜罐：每格液面高度 = 剩余比例。几何、配色与 design/prototype-honey/index.html 的 Jar 一一对应。

/// 一格液体：带弧形液面的闭合路径。`slosh` 为液面晃动幅度（pt，正负皆可）。
/// 可动画：小组件等无逐帧驱动的场景，直接靠 `animatableData` 补间液位。
public struct HoneyLiquidShape: Shape {
    public var level: Double
    public var slosh: Double
    public var surfaceOnly: Bool
    public init(level: Double, slosh: Double = 0, surfaceOnly: Bool = false) {
        self.level = level; self.slosh = slosh; self.surfaceOnly = surfaceOnly
    }
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, slosh) }
        set { level = newValue.first; slosh = newValue.second }
    }
    public func path(in rect: CGRect) -> Path {
        // 允许略高于 1：回灌时的过冲让液面短暂顶到罐口。
        let fill = min(1.03, max(0, level))
        let amp = min(9, max(-9, slosh))
        let y = rect.maxY - fill * rect.height
        let tilt = amp * 0.5
        let x0 = rect.minX, width = rect.width
        let mid = CGPoint(x: x0 + width * 0.5, y: y)
        let control = CGPoint(x: x0 + width * 0.25, y: y - amp + tilt * 0.5)
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y + tilt))
        path.addQuadCurve(to: mid, control: control)
        // SVG 的 T 指令：控制点关于中点镜像，保证液面在中点处光滑。
        path.addQuadCurve(to: CGPoint(x: x0 + width, y: y - tilt),
                          control: CGPoint(x: 2 * mid.x - control.x, y: 2 * mid.y - control.y))
        guard !surfaceOnly else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 2))
        path.addLine(to: CGPoint(x: x0, y: rect.maxY + 2))
        path.closeSubpath()
        return path
    }
}

/// 液位弹簧的一段运动：从 `from` 以初速 `velocity` 奔向 `target`，按 `BearMotion.fluidSpring` 解析求值。
struct LiquidMotion: Equatable {
    var from: Double
    var target: Double
    var velocity: Double
    var start: Date

    static func resting(_ value: Double, at date: Date) -> LiquidMotion {
        LiquidMotion(from: value, target: value, velocity: 0, start: date)
    }
    var duration: TimeInterval { from == target && velocity == 0 ? 0 : BearMotion.fluidSpring.settlingDuration }
    func sample(at date: Date) -> (value: Double, velocity: Double) {
        let elapsed = date.timeIntervalSince(start)
        guard elapsed < duration, elapsed >= 0 else { return (elapsed < 0 ? from : target, 0) }
        let spring = BearMotion.fluidSpring
        let delta = target - from
        return (from + spring.value(target: delta, initialVelocity: velocity, time: elapsed),
                spring.velocity(target: delta, initialVelocity: velocity, time: elapsed))
    }
    /// 中途改目标：从当前位置与速度接续，手感连续、可打断。
    func retargeted(to value: Double, at date: Date) -> LiquidMotion {
        let now = sample(at: date)
        return LiquidMotion(from: now.value, target: value, velocity: now.velocity, start: date)
    }
}

/// 双格（或单格）蜜罐。
public struct BearHoneyJar: View {
    public struct Cell: Equatable, Sendable {
        /// 液位 0...1。
        public var level: Double
        /// 低于警示阈值：液体转余烬色、数字转警示墨色。
        public var warn: Bool
        /// 罐内数字（不含 %）；nil 显示「–」。
        public var value: String?
        public var label: String
        public init(level: Double, warn: Bool, value: String?, label: String) {
            self.level = min(1, max(0, level)); self.warn = warn; self.value = value; self.label = label
        }
    }
    public enum Shell: Sendable { case glass, plain }

    let cells: [Cell]
    let stale: Bool
    let asleep: Bool
    let cornerRadius: CGFloat
    let shell: Shell
    let numberSize: CGFloat
    @State private var motions: [LiquidMotion] = []
    @State private var moving = false
    @State private var motionEpoch = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bearReduceMotion) private var reduceMotion

    public init(cells: [Cell], stale: Bool = false, asleep: Bool = false,
                cornerRadius: CGFloat = 28, shell: Shell = .glass, numberSize: CGFloat = 30) {
        self.cells = cells; self.stale = stale; self.asleep = asleep
        self.cornerRadius = cornerRadius; self.shell = shell; self.numberSize = numberSize
    }

    private var targets: [Double] { cells.map { asleep ? 0 : $0.level } }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        TimelineView(.animation(minimumInterval: nil, paused: !moving || reduceMotion)) { context in
            GeometryReader { geometry in
                let count = max(1, cells.count)
                let width = geometry.size.width / CGFloat(count)
                ZStack(alignment: .topLeading) {
                    ForEach(cells.indices, id: \.self) { index in
                        liquid(index: index, date: context.date, size: CGSize(width: width, height: geometry.size.height))
                            .frame(width: width, height: geometry.size.height)
                            .offset(x: CGFloat(index) * width)
                    }
                    ForEach(1..<count, id: \.self) { index in
                        Rectangle().fill(BearTheme.surface(scheme))
                            .frame(width: 3, height: geometry.size.height)
                            .offset(x: CGFloat(index) * width - 1.5)
                    }
                }
            }
        }
            .clipShape(shape)
            .overlay { labels }
            .background { shellBackground(shape) }
            .overlay {
            // 罐口高光 + 细边；未连接时边框虚线。
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(scheme == .dark ? 0.22 : 0.95), location: 0),
                                                      .init(color: .white.opacity(0), location: 0.35)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            shape.strokeBorder(BearTheme.separator(scheme),
                               style: StrokeStyle(lineWidth: 0.5, dash: asleep ? [4, 5] : []))
        }
            .onAppear { motions = targets.map { LiquidMotion.resting($0, at: .now) } }
            .onChange(of: JarKey(cells: cells, asleep: asleep)) { old, new in
            // 旧状态无读数（冷启动缓存未到、未连接、格数变化）时直接落位，不播放倒灌。
            let snap = old.asleep || old.cells.count != new.cells.count || old.cells.contains { $0.value == nil }
            retarget(targets, snap: snap)
        }
            .task(id: motionEpoch) {
            // 最长一段运动结束后暂停时间线：静止即零帧。
            let remaining = motions.map { max(0, $0.duration - Date.now.timeIntervalSince($0.start)) }.max() ?? 0
            guard remaining > 0 else { moving = false; return }
            do { try await Task.sleep(for: .seconds(remaining + 0.05)) } catch { return }
            moving = false
        }
            .accessibilityHidden(true)
    }

    private struct JarKey: Equatable { let cells: [Cell]; let asleep: Bool }

    private func retarget(_ new: [Double], snap: Bool) {
        let now = Date.now
        guard !snap, motions.count == new.count, !reduceMotion else {
            motions = new.map { LiquidMotion.resting($0, at: now) }; return
        }
        motions = zip(motions, new).map { motion, value in
            motion.target == value ? motion : motion.retargeted(to: value, at: now)
        }
        moving = true
        motionEpoch &+= 1
    }

    @ViewBuilder private func liquid(index: Int, date: Date, size: CGSize) -> some View {
        let sample: (value: Double, velocity: Double) = motions.indices.contains(index)
            ? motions[index].sample(at: date) : (value: targets[index], velocity: 0)
        // 晃动幅度由液位速度推出；Reduce Motion 下液面保持水平。
        let slosh = reduceMotion ? 0 : sample.velocity * size.height * 0.03
        let cell = cells[index]
        ZStack {
            liquidFill(warn: false, level: sample.value, slosh: slosh)
            liquidFill(warn: true, level: sample.value, slosh: slosh)
                .animation(BearMotion.smooth) { $0.opacity(cell.warn && !asleep ? 1 : 0) }
            HoneyLiquidShape(level: sample.value, slosh: slosh, surfaceOnly: true)
                .stroke(.white.opacity(scheme == .dark ? 0.35 : 0.7), lineWidth: 1.5)
                .opacity(sample.value > 0.03 ? 1 : 0)
        }
            .saturation(stale ? 0.2 : 1)
            .opacity(stale ? 0.5 : 1)
    }

    private func liquidFill(warn: Bool, level: Double, slosh: Double) -> some View {
        HoneyLiquidShape(level: level, slosh: slosh)
            .fill(LinearGradient(colors: warn ? BearTheme.ember(scheme) : BearTheme.honey(scheme),
                                 startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private func shellBackground(_ shape: RoundedRectangle) -> some View {
        switch shell {
            case .glass:
            shape.fill(Color.gray.opacity(scheme == .dark ? 0.06 : 0.08))
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.07), radius: 11, y: 8)
            case .plain:
            shape.fill(BearTheme.track(scheme))
        }
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                let cell = cells[index]
                VStack {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(asleep ? "–" : cell.value ?? "–")
                            .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: cell.level))
                            .foregroundStyle(cell.warn && !asleep ? BearTheme.danger(scheme) : BearTheme.text(scheme))
                        if !asleep && cell.value != nil {
                            Text("%").font(.system(size: numberSize * 0.43, weight: .bold, design: .rounded))
                                .foregroundStyle(BearTheme.secondaryText(scheme))
                        }
                    }
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(cell.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(labelColor(cell))
                        .lineLimit(1)
                }
                    .padding(.top, 14).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
            }
        }
            .animation(BearMotion.snappy, value: cells)
    }

    private func labelColor(_ cell: Cell) -> Color {
        if asleep || cell.level < 0.16 { return BearTheme.secondaryText(scheme) }
        return cell.warn ? .white : BearTheme.honeyInk(scheme)
    }
}

/// 横向蜜条：详情页的窗口行用，液位用 fluid 弹簧补间。
public struct BearHoneyBar: View {
    let fraction: Double
    let warn: Bool
    let stale: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bearReduceMotion) private var reduceMotion
    public init(fraction: Double, warn: Bool, stale: Bool = false) {
        self.fraction = min(1, max(0, fraction)); self.warn = warn; self.stale = stale
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BearTheme.track(scheme))
                Capsule()
                    .fill(LinearGradient(colors: warn ? BearTheme.ember(scheme) : BearTheme.honey(scheme),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fraction > 0 ? geometry.size.height : 0, geometry.size.width * fraction))
                    .saturation(stale ? 0.2 : 1).opacity(stale ? 0.5 : 1)
            }
        }
            .frame(height: 10)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.fluid, value: fraction)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.smooth, value: warn)
            .accessibilityHidden(true)
    }
}
