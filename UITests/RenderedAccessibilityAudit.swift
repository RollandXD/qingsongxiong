import UIKit
import XCTest

/// 原生 OCR 对短中文、实时倒计时和合成层偶有误判。
/// 不无条件忽略 contrast：必须在该元素的实际截图中找到语义墨色，
/// 再用实际像素和局部背景计算 WCAG；无法核实时继续让原生审计失败。
@MainActor
func auditRenderedAccessibility(_ app: XCUIApplication, test: XCTestCase) throws {
    // 一次审计里复用同一张全屏截图：像素数据完全一样，只是不再为每个对比度问题
    // 重新截一次图（截屏+编码是这条链最慢的一步）。一旦因滚动改变了版面就作废重拍。
    var cached: (image: CGImage, generation: Int)?
    var generation = 0
    try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped, .contrast]) { issue in
        guard issue.auditType == .contrast, let element = issue.element else {
            // 不只报 label：把 frame、标识和屏幕尺寸一起打出来，
            // 否则 “Text clipped Claude” 这种信息只能靠猜是哪一个 Claude。
            let target = issue.element
            print("BEAR_AUDIT_UNRESOLVED \(issue.compactDescription)"
                + " element=\(target?.label ?? "nil")"
                + " id=\(target?.identifier ?? "nil")"
                + " frame=\(target?.frame.debugDescription ?? "nil")"
                + " screen=\(Int(app.frame.width))x\(Int(app.frame.height))")
            return false
        }
        // 原生审计也可能返回 ScrollView 中尚未完整进入屏幕的页脚。
        // 先把真实元素滚入视口，再采完整截图；绝不裁掉越界部分或直接忽略。
        let before = element.frame
        guard revealForContrast(element, in: app, test: test) else {
            print("BEAR_RENDERED_UNRESOLVED \(element.label) frame=\(element.frame)")
            return false
        }
        if element.frame != before { generation += 1 }
        if cached?.generation != generation {
            guard let image = app.screenshot().image.cgImage else {
                print("BEAR_RENDERED_UNRESOLVED \(element.label) frame=\(element.frame)")
                return false
            }
            cached = (image, generation)
        }
        guard let image = cached?.image,
              let result = RenderedContrast.measure(image, rect: element.frame, screen: app.frame) else {
            print("BEAR_RENDERED_UNRESOLVED \(element.label) frame=\(element.frame)")
            return false
        }
        guard result.ratio >= 4.5 else {
            print("BEAR_RENDERED_LOW \(result.ratio) \(element.label)")
            return false
        }
        print("BEAR_RENDERED_CONTRAST \(result.ratio) inkPixels=\(result.inkPixels) \(element.label)")
        return true
    }
}

/// 内容视口不等于整块屏幕：导航栏、soft scroll edge 和底部安全区都不能拿来采文字。
/// 额外留一行高度让文字完整进入稳定内容区，阈值仍为 4.5:1，不裁切或跳过问题。
private func contrastViewport(screen: CGRect, navigationBar: CGRect?) -> CGRect {
    let top = min(screen.maxY, max(screen.minY + 44, (navigationBar?.maxY ?? screen.minY) + 44))
    let bottom = max(top, screen.maxY - 34)
    return CGRect(x: screen.minX, y: top, width: screen.width, height: bottom - top)
}

/// 最多滚动三次；仍被遮挡、越界、尺寸异常或没有滚动容器时保持审计失败。
@MainActor
private func revealForContrast(_ element: XCUIElement, in app: XCUIApplication, test: XCTestCase) -> Bool {
    let original = element.frame
    for attempt in 0...3 {
        let screen = app.frame
        let bar = app.navigationBars.firstMatch
        let viewport = contrastViewport(screen: screen, navigationBar: bar.exists ? bar.frame : nil)
        let frame = element.frame
        guard frame.width > 2, frame.height > 2,
              frame.width <= viewport.width, frame.height <= viewport.height else { return false }
        if viewport.contains(frame) {
            if attempt > 0 {
                print("BEAR_AUDIT_REVEALED \(element.label) from=\(original) to=\(frame)")
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "contrast-revealed-element"
                attachment.lifetime = .keepAlways
                test.add(attachment)
            }
            return true
        }
        let scroll = app.scrollViews.firstMatch
        guard attempt < 3, scroll.exists else { return false }
        if frame.maxY > viewport.maxY { scroll.swipeUp() }
        else if frame.minY < viewport.minY { scroll.swipeDown() }
        else { return false }
    }
    return false
}

@MainActor
final class RenderedContrastTests: XCTestCase {
    func testContrastViewportRejectsOccludedNavigationAndHomeIndicatorRegions() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let bar = CGRect(x: 0, y: 62, width: 402, height: 44)
        let viewport = contrastViewport(screen: screen, navigationBar: bar)
        XCTAssertFalse(viewport.contains(CGRect(x: 32, y: 44, width: 102, height: 16)))
        XCTAssertFalse(viewport.contains(CGRect(x: 32, y: 128, width: 102, height: 16)))
        XCTAssertFalse(viewport.contains(CGRect(x: 32, y: 850, width: 102, height: 16)))
        XCTAssertTrue(viewport.contains(CGRect(x: 32, y: 200, width: 102, height: 16)))
        XCTAssertTrue(screen.contains(viewport))
        XCTAssertTrue(contrastViewport(screen: screen, navigationBar: nil)
            .contains(CGRect(x: 32, y: 48, width: 102, height: 16)))
    }

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
        let ink = UIColor(red: 94 / 255.0, green: 93 / 255.0, blue: 89 / 255.0, alpha: 1)
        let readable = try XCTUnwrap(RenderedContrast.measure(image(ink: ink, background: .white), rect: rect, screen: rect))
        XCTAssertGreaterThan(readable.ratio, 4.5)
        // 浅色卡片与深色模式的白字 token 相近，不能把背景当成另一种文字墨色。
        let pale = UIColor(red: 244 / 255.0, green: 242 / 255.0, blue: 236 / 255.0, alpha: 1)
        let paleResult = try XCTUnwrap(RenderedContrast.measure(image(ink: ink, background: pale), rect: rect, screen: rect))
        XCTAssertGreaterThan(paleResult.ratio, 4.5)
        let gradient = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, pale.cgColor] as CFArray
            let ramp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
            context.cgContext.drawLinearGradient(ramp, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            ("已用 28%" as NSString).draw(at: CGPoint(x: 3, y: 3), withAttributes: [
                .foregroundColor: ink, .font: UIFont.systemFont(ofSize: 18),
            ])
        }.cgImage!
        let gradientResult = try XCTUnwrap(RenderedContrast.measure(gradient, rect: rect, screen: rect))
        XCTAssertGreaterThan(gradientResult.ratio, 4.5)
        let lowContrast = RenderedContrast.measure(image(ink: ink, background: .darkGray), rect: rect, screen: rect)
        XCTAssertLessThan(lowContrast?.ratio ?? 0, 4.5)
        XCTAssertNil(RenderedContrast.measure(image(ink: .lightGray, background: .white), rect: rect, screen: rect))
        // 即使图片本身可读，也不能只裁可见部分来放过越界的元素。
        let readableImage = image(ink: ink, background: .white)
        for offscreen in [rect.offsetBy(dx: 0, dy: 1), rect.offsetBy(dx: 0, dy: -1),
                          rect.offsetBy(dx: 1, dy: 0), rect.offsetBy(dx: -1, dy: 0)] {
            XCTAssertNil(RenderedContrast.measure(readableImage, rect: offscreen, screen: rect))
        }
    }
}

private enum RenderedContrast {
    struct Result { let ratio: Double; let inkPixels: Int }
    // 与 BearTheme 的主/次文字、状态文字一致；不把图表系列色当文字墨色。
    static let inks: [[Int]] = [
        [29, 29, 31], [94, 93, 89], [154, 91, 0], [31, 122, 58], [198, 42, 33],
        [245, 244, 239], [183, 181, 174], [255, 179, 64], [48, 209, 88], [255, 105, 97],
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
        // 先从文字框边缘估计局部底色：墨色在渐变上可能反而是全图众数。
        // 中位数抑制字形碰到边缘的少量像素；随后只匹配与该底色对比足够的语义墨色。
        var border: [[Int]] = []
        for y in 0..<height {
            for x in 0..<width where x < 2 || y < 2 || x >= width - 2 || y >= height - 2 {
                let offset = (y * width + x) * 4
                border.append((0..<3).map { Int(pixels[offset + $0]) })
            }
        }
        guard !border.isEmpty else { return nil }
        border.sort { luminance($0) < luminance($1) }
        let background = border[border.count / 2]
        let bgL = luminance(background)
        func contrast(_ rgb: [Int]) -> Double {
            let inkL = luminance(rgb)
            return (max(inkL, bgL) + 0.05) / (min(inkL, bgL) + 0.05)
        }
        let candidates = inks.filter { contrast($0) >= 4.5 }
        var inkPixels: [[Int]] = []
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = (0..<3).map { Int(pixels[offset + $0]) }
            if candidates.contains(where: { ink in zip(ink, rgb).allSatisfy { abs($0 - $1) <= 5 } }) {
                inkPixels.append(rgb)
            }
        }
        guard inkPixels.count >= max(24, width * height / 100) else { return nil }
        return Result(ratio: inkPixels.map(contrast).min() ?? 0, inkPixels: inkPixels.count)
    }
}
