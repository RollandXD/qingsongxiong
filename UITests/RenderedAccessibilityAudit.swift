import UIKit
import XCTest

/// 原生 OCR 对短中文、实时倒计时和合成层偶有误判。
/// 不无条件忽略 contrast：必须在该元素的实际截图中找到语义墨色，
/// 再用实际像素和局部背景计算 WCAG；无法核实时继续让原生审计失败。
@MainActor
func auditRenderedAccessibility(_ app: XCUIApplication, test: XCTestCase) throws {
    try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped, .contrast]) { issue in
        guard issue.auditType == .contrast, let element = issue.element else {
            print("BEAR_AUDIT_UNRESOLVED \(issue.compactDescription) \(issue.element?.label ?? "nil")")
            return false
        }
        guard let image = app.screenshot().image.cgImage,
              let result = RenderedContrast.measure(image, rect: element.frame, screen: app.frame),
              result.ratio >= 4.5 else { return false }
        print("BEAR_RENDERED_CONTRAST \(result.ratio) inkPixels=\(result.inkPixels) \(element.label)")
        return true
    }
}

@MainActor
final class RenderedContrastTests: XCTestCase {
    func testRenderedGateAcceptsReadableInkAndRejectsLowContrast() throws {
        let size = CGSize(width: 180, height: 36)
        func image(ink: UIColor, background: UIColor) -> CGImage {
            UIGraphicsImageRenderer(size: size).image { context in
                background.setFill(); context.fill(CGRect(origin: .zero, size: size))
                ("已用 28%" as NSString).draw(at: CGPoint(x: 3, y: 3), withAttributes: [
                    .foregroundColor: ink, .font: UIFont.systemFont(ofSize: 18),
                ])
            }.cgImage!
        }
        let rect = CGRect(origin: .zero, size: size)
        let ink = UIColor(red: 53 / 255.0, green: 58 / 255.0, blue: 52 / 255.0, alpha: 1)
        let readable = try XCTUnwrap(RenderedContrast.measure(image(ink: ink, background: .white), rect: rect, screen: rect))
        XCTAssertGreaterThan(readable.ratio, 4.5)
        let lowContrast = RenderedContrast.measure(image(ink: ink, background: .darkGray), rect: rect, screen: rect)
        XCTAssertLessThan(lowContrast?.ratio ?? 0, 4.5)
        XCTAssertNil(RenderedContrast.measure(image(ink: .lightGray, background: .white), rect: rect, screen: rect))
    }
}

private enum RenderedContrast {
    struct Result { let ratio: Double; let inkPixels: Int }
    // 与 BearTheme 的主/次文字、状态文字一致；不把图表系列色当文字墨色。
    static let inks: [[Int]] = [
        [37, 40, 35], [53, 58, 52], [149, 97, 0], [38, 120, 100], [184, 64, 68],
        [244, 243, 239], [195, 201, 190], [228, 188, 104], [108, 201, 173], [241, 138, 141],
    ]
    static func luminance(_ rgb: [Int]) -> Double {
        let linear = rgb.map { value -> Double in
            let s = Double(value) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
    static func measure(_ image: CGImage, rect: CGRect, screen: CGRect) -> Result? {
        guard screen.width > 0, screen.contains(rect), rect.width > 2, rect.height > 2 else { return nil }
        let scale = Double(image.width) / screen.width
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                          width: rect.width * scale, height: rect.height * scale).integral
        guard let clipped = image.cropping(to: crop) else { return nil }
        let width = clipped.width, height = clipped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(clipped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var histogram: [Int: Int] = [:]
        var inkPixels: [[Int]] = []
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = (0..<3).map { Int(pixels[offset + $0]) }
            let key = (rgb[0] / 8 << 10) | (rgb[1] / 8 << 5) | (rgb[2] / 8)
            histogram[key, default: 0] += 1
            if inks.contains(where: { ink in zip(ink, rgb).allSatisfy { abs($0 - $1) <= 5 } }) {
                inkPixels.append(rgb)
            }
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key,
              inkPixels.count >= max(24, width * height / 100) else { return nil }
        let bg = [(background >> 10) * 8 + 4, ((background >> 5) & 31) * 8 + 4, (background & 31) * 8 + 4]
        let bgL = luminance(bg)
        let ratio = inkPixels.map { rgb in
            let inkL = luminance(rgb)
            return (max(inkL, bgL) + 0.05) / (min(inkL, bgL) + 0.05)
        }.min() ?? 0
        return Result(ratio: ratio, inkPixels: inkPixels.count)
    }
}
