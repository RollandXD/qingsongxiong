import SwiftUI

public enum BearTheme {
    public static let caramel = Color(red: 0.58, green: 0.32, blue: 0.16)
    private static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    public static func background(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x141615 : 0xF7F6F2) }
    public static func surface(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x202320 : 0xFFFFFF) }
    public static func text(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xF4F3EF : 0x252823) }
    public static func secondaryText(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xC3C9BE : 0x353A34) }
    public static func accent(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xD8AA8C : 0x9F6042) }
    public static func track(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x353A35 : 0xE9EBE5) }
    public static func warning(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xE4BC68 : 0x956100) }
    public static func success(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x6CC9AD : 0x267864) }
    public static func danger(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xF18A8D : 0xB84044) }
    public static func series(_ index: Int, _ scheme: ColorScheme) -> Color {
        let light: [UInt32] = [0x267864, 0xA95E40, 0x4F6FE8]
        let dark: [UInt32] = [0x73C4B0, 0xDCA88B, 0x91A7FF]
        let values = scheme == .dark ? dark : light
        return rgb(values[min(2, max(0, index))])
    }
    /// 玻璃卡底纹：四角网格渐变，系列色只在一角极淡出现。
    public static func meshStops(tint: Color, _ scheme: ColorScheme) -> [Color] {
        let base = surface(scheme).opacity(0)
        return [tint.opacity(scheme == .dark ? 0.16 : 0.10), base, base, accent(scheme).opacity(scheme == .dark ? 0.06 : 0.04)]
    }
    /// 页面背景纸感渐变。
    public static func paper(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [rgb(scheme == .dark ? 0x1A1C1A : 0xFBF8F1), background(scheme)],
                       startPoint: .top, endPoint: .bottom)
    }
    public static func quotaColor(_ remaining: Double, series: Int, scheme: ColorScheme) -> Color {
        remaining <= 0 ? danger(scheme) : remaining <= 20 ? warning(scheme) : self.series(series, scheme)
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
