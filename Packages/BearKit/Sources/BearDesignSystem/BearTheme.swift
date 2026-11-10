import SwiftUI

public enum BearTheme {
    public static let caramel = Color(red: 0.58, green: 0.32, blue: 0.16)
    private static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    // 纸白底：不用纯白/纯黑，取 Claude 式暖纸色；卡片比底亮一级。
    public static func background(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x262624 : 0xF4F2EC) }
    public static func surface(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x30302E : 0xFBFAF7) }
    // 文字墨色一律实色（RenderedAccessibilityAudit 按实色像素核对比度，≥4.5）。
    public static func text(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xF5F4EF : 0x1D1D1F) }
    public static func secondaryText(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xB7B5AE : 0x5E5D59) }
    /// App tint = systemOrange。
    public static func accent(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF9F0A : 0xFF9500) }
    /// 可作文字的强调墨色（systemOrange 在纸白上对比不足）。
    public static func accentInk(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFFB340 : 0x9A5B00) }
    public static func track(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x3A3A37 : 0xE8E5DC) }
    public static func separator(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x45453F : 0xD9D6CC) }
    public static func warning(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFFB340 : 0x9A5B00) }
    public static func success(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x30D158 : 0x1F7A3A) }
    public static func danger(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF6961 : 0xC62A21) }
    /// 平台系列色（系统色）：0 Codex = systemGreen，1 Claude = systemBrown，2 DeepSeek = systemIndigo。
    /// 只用于圆点、图标和液体之外的标识，不作文字墨色。
    public static func series(_ index: Int, _ scheme: ColorScheme) -> Color {
        let light: [UInt32] = [0x34C759, 0xA2845E, 0x5856D6]
        let dark: [UInt32] = [0x30D158, 0xAC8E68, 0x5E5CE6]
        let values = scheme == .dark ? dark : light
        return rgb(values[min(2, max(0, index))])
    }
    /// 中转站 = systemCyan。
    public static func relay(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x64D2FF : 0x32ADE6) }

    /// 蜂蜜液体：systemYellow → systemOrange 自上而下。
    public static func honey(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark ? [rgb(0xFFD60A), rgb(0xFF9F0A)] : [rgb(0xFFCC00), rgb(0xFF9500)]
    }
    /// 余烬液体（低于警示阈值）：唯一警示色 systemRed。
    public static func ember(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark ? [rgb(0xFF6B60), rgb(0xFF453A)] : [rgb(0xFF6961), rgb(0xFF3B30)]
    }
    /// 浸在蜂蜜里的小字墨色。
    public static func honeyInk(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x4A2A00 : 0x5A3A00) }

    /// 旧玻璃卡底纹：新设计不再上色，保留签名，四角全透明。
    public static func meshStops(tint: Color, _ scheme: ColorScheme) -> [Color] {
        Array(repeating: surface(scheme).opacity(0), count: 4)
    }
    /// 页面背景：纸白实色（保留 LinearGradient 签名，两端同色）。
    public static func paper(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [background(scheme), background(scheme)], startPoint: .top, endPoint: .bottom)
    }
    /// 额度主色：低于警示阈值统一转警示色，否则用平台色。阈值与 QuotaThresholds.watch 同为 20。
    public static func quotaColor(_ remaining: Double, series: Int, scheme: ColorScheme) -> Color {
        remaining <= 20 ? danger(scheme) : self.series(series, scheme)
    }
}

public struct BearMark: View {
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(BearTheme.caramel).frame(width: side * 0.34, height: side * 0.34)
                    .offset(x: -side * 0.27, y: -side * 0.24)
                Circle().fill(BearTheme.caramel).frame(width: side * 0.34, height: side * 0.34)
                    .offset(x: side * 0.27, y: -side * 0.24)
                Ellipse().fill(BearTheme.caramel).frame(width: side * 0.87, height: side * 0.76)
                Ellipse().fill(Color(red: 1, green: 0.9, blue: 0.73))
                    .frame(width: side * 0.4, height: side * 0.29).offset(y: side * 0.12)
                HStack(spacing: side * 0.25) {
                    Circle().frame(width: side * 0.055, height: side * 0.055)
                    Circle().frame(width: side * 0.055, height: side * 0.055)
                }.foregroundStyle(Color(red: 0.18, green: 0.12, blue: 0.08)).offset(y: -side * 0.025)
                Ellipse().fill(Color(red: 0.18, green: 0.12, blue: 0.08))
                    .frame(width: side * 0.085, height: side * 0.06).offset(y: side * 0.075)
            }.frame(width: geo.size.width, height: geo.size.height)
        }.accessibilityHidden(true)
    }
}

public struct BearStatusRow: View {
    @Environment(\.colorScheme) private var scheme
    private let title: String
    private let passed: Bool
    public init(_ title: String, passed: Bool) { self.title = title; self.passed = passed }
    public var body: some View {
        LabeledContent(title) {
            Label(passed ? "通过" : "待验证", systemImage: passed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(passed ? BearTheme.success(scheme) : BearTheme.secondaryText(scheme))
        }.accessibilityElement(children: .combine)
    }
}
