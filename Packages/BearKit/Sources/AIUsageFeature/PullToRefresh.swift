import BearDesignSystem
import SwiftUI

extension View {
    func bearPullToRefresh(enabled: Bool, action: @escaping @MainActor () async -> Bool) -> some View {
        modifier(BearPullToRefresh(enabled: enabled, action: action))
    }
}

private struct BearPullToRefresh: ViewModifier {
    let enabled: Bool
    let action: @MainActor () async -> Bool
    @State private var interaction = PullRefreshInteraction()
    @State private var dragging = false
    @State private var settled = false
    @State private var succeeded = false
    @State private var completion = 0
    @State private var task: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Int.self) { geometry in
                // 4pt 量化；只驱动小型下拉提示，不参与列表布局或网络请求。
                Int(min(160, max(0, -(geometry.contentOffset.y + geometry.contentInsets.top)))) / 4 * 4
            } action: { _, distance in
                if dragging { interaction.observe(distance: Double(distance)) }
            }
            .onScrollPhaseChange { old, new in
                if !dragging && (new == .tracking || new == .interacting) { interaction.begin() }
                if old == .interacting && new != .interacting && new != .tracking,
                   interaction.release(enabled: enabled) {
                    task = Task { @MainActor in
                        defer { interaction.finish(); settled = false }
                        succeeded = await action()
                        guard !Task.isCancelled, scenePhase == .active else { return }
                        settled = true; completion &+= 1
                        interaction.finish()
                        // 结果只短暂呈现一次，不延长正在请求的状态。
                        try? await Task.sleep(for: .milliseconds(450))
                    }
                }
                dragging = new == .tracking || new == .interacting
            }
            .overlay(alignment: .top) {
                PullBearIndicator(progress: interaction.progress, refreshing: interaction.refreshing,
                                  settled: settled, succeeded: succeeded, completion: completion, enabled: enabled)
                    .padding(.top, 2)
                    .offset(y: interaction.refreshing || settled ? 0 : min(8, interaction.distance - 50))
                    .opacity(interaction.distance > 8 || interaction.refreshing || settled ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(!interaction.refreshing && !settled)
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { task?.cancel(); interaction.finish(); settled = false } }
            .onDisappear { task?.cancel(); interaction.finish() }
    }
}

private struct PullBearIndicator: View {
    let progress: Double
    let refreshing: Bool
    let settled: Bool
    let succeeded: Bool
    let completion: Int
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 9) {
            Group {
                if refreshing && !reduceMotion {
                    // 只有真实请求期间才存在动画时间线；静止不轮询、不持续装饰。
                    TimelineView(.animation) { tick in
                        BearMark().rotationEffect(.degrees(tick.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
                    }
                } else {
                    BearMoodMark(mood: settled ? (succeeded ? .calm : .watchful) : .asleep)
                        .scaleEffect(reduceMotion ? 1 : 0.65 + progress * 0.35)
                        .keyframeAnimator(initialValue: 0.0, trigger: completion) { content, tilt in
                            content.rotationEffect(.degrees(reduceMotion ? 0 : tilt))
                        } keyframes: { _ in
                            CubicKeyframe(10, duration: 0.12)
                            SpringKeyframe(0, duration: 0.25)
                        }
                }
            }.frame(width: 30, height: 30)
            Text(settled ? (succeeded ? "读数已核实" : "已保留原读数") : refreshing ? "熊在核实读数…" : !enabled ? "连接后可刷新" : progress >= 1 ? "松手，熊来刷新" : "下拉叫醒轻松熊")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine).accessibilityIdentifier("bear-pull-refresh")
    }
}
