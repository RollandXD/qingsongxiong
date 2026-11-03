import SwiftUI

public enum BearTheme {
    public static let caramel = Color(red: 0.58, green: 0.32, blue: 0.16)
    public static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.09, blue: 0.08) : Color(red: 1, green: 0.975, blue: 0.94)
    }
    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.18, green: 0.15, blue: 0.12) : .white
    }
    public static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.71, blue: 0.45) : caramel
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
    private let title: String
    private let passed: Bool
    public init(_ title: String, passed: Bool) { self.title = title; self.passed = passed }
    public var body: some View {
        LabeledContent(title) {
            Label(passed ? "通过" : "待验证", systemImage: passed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(passed ? .green : .secondary)
        }.accessibilityElement(children: .combine)
    }
}
