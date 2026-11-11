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
        let label = element.label
        let before = element.frame
        guard let frame = revealForContrast(element, in: app, test: test, didScroll: { generation += 1 }) else {
            print("BEAR_RENDERED_UNRESOLVED \(label) frame=\(before)")
            return false
        }
        if cached?.generation != generation {
            guard let image = app.screenshot().image.cgImage else {
                print("BEAR_RENDERED_UNRESOLVED \(label) frame=\(frame)")
                return false
            }
            cached = (image, generation)
        }
        guard let image = cached?.image,
              let result = RenderedContrast.measure(image, rect: frame, screen: app.frame) else {
            print("BEAR_RENDERED_UNRESOLVED \(label) frame=\(frame)")
            return false
        }
        guard result.ratio >= 4.5 else {
            print("BEAR_RENDERED_LOW \(result.ratio) \(label)")
            return false
        }
        print("BEAR_RENDERED_CONTRAST \(result.ratio) inkPixels=\(result.inkPixels) \(label)")
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

/// 固定导航标题不能靠滚动“滚入正文”；只有完整位于导航栏和屏幕内才允许原位采样。
private func fixedChromeViewport(frame: CGRect, screen: CGRect, navigationBar: CGRect?,
                                 isNavigationElement: Bool) -> CGRect? {
    guard isNavigationElement, let navigationBar, screen.contains(frame), navigationBar.contains(frame) else { return nil }
    return navigationBar.intersection(screen)
}

/// 小幅、限距的露出动作；起点在左侧内容边缘，避开图表和时间尺的交互区域。
/// 整屏 swipe 容易把顶部短文字一下甩到底部，又反向甩回去，三次也无法稳定采样。
private func contrastRevealDrag(frame: CGRect, viewport: CGRect) -> (start: CGPoint, end: CGPoint)? {
    guard viewport.height > 72, !viewport.contains(frame) else { return nil }
    let distance: CGFloat
    if frame.minY < viewport.minY {
        distance = min(viewport.height / 3, viewport.minY - frame.minY + 24)
    } else if frame.maxY > viewport.maxY {
        distance = -min(viewport.height / 3, frame.maxY - viewport.maxY + 24)
    } else { return nil }
    let start = CGPoint(x: viewport.minX + 8, y: viewport.midY)
    return (start, CGPoint(x: start.x, y: start.y + distance))
}

/// 同名文字跨平台重复时，只允许按滚动不改变的横向槽位和字框尺寸重新绑定。
/// 不按“最近的 y”猜：滚动正会改变 y；相同槽位仍有多个候选时必须继续失败。
private func sameContrastTextSlot(_ frame: CGRect, original: CGRect) -> Bool {
    abs(frame.minX - original.minX) <= 1
        && abs(frame.width - original.width) <= 1
        && abs(frame.height - original.height) <= 1
}

/// 最多滚动三次；滚动后重新定位唯一元素，不继续持有 SwiftUI 已销毁的 AX binding。
/// 固定 chrome 原位采实际像素；其余仍要求进入无遮挡正文区，失败不跳过。
@MainActor
private func revealForContrast(_ element: XCUIElement, in app: XCUIApplication, test: XCTestCase,
                               didScroll: () -> Void) -> CGRect? {
    let original = element.frame
    let label = element.label
    let identifier = element.identifier
    let type = element.elementType
    for attempt in 0...3 {
        let current: XCUIElement
        if attempt == 0 {
            current = element
        } else {
            let predicate = identifier.isEmpty
                ? NSPredicate(format: "label == %@", label)
                : NSPredicate(format: "identifier == %@", identifier)
            let matches = app.descendants(matching: type).matching(predicate).allElementsBoundByIndex
            let candidates = matches.filter { sameContrastTextSlot($0.frame, original: original) }
            guard candidates.count == 1 else {
                print("BEAR_AUDIT_REBIND_UNRESOLVED \(label) id=\(identifier)"
                    + " matches=\(matches.count) sameSlot=\(candidates.count) original=\(original)")
                return nil
            }
            current = candidates[0]
        }
        guard current.exists else { return nil }
        let screen = app.frame
        let bar = app.navigationBars.firstMatch
        let navigationFrame = bar.exists ? bar.frame : nil
        let frame = current.frame
        let predicate = identifier.isEmpty
            ? NSPredicate(format: "label == %@", label)
            : NSPredicate(format: "identifier == %@", identifier)
        let inNavigation = bar.exists && bar.descendants(matching: type).matching(predicate)
            .allElementsBoundByIndex.contains { $0.frame == frame }
        let viewport = fixedChromeViewport(frame: frame, screen: screen, navigationBar: navigationFrame,
                                           isNavigationElement: inNavigation)
            ?? contrastViewport(screen: screen, navigationBar: navigationFrame)
        guard frame.width > 2, frame.height > 2,
              frame.width <= viewport.width, frame.height <= viewport.height else { return nil }
        if viewport.contains(frame) {
            if attempt > 0 {
                print("BEAR_AUDIT_REVEALED \(label) from=\(original) to=\(frame)")
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "contrast-revealed-element"
                attachment.lifetime = .keepAlways
                test.add(attachment)
            }
            return frame
        }
        let scroll = app.scrollViews.firstMatch
        guard attempt < 3, scroll.exists,
              let drag = contrastRevealDrag(frame: frame, viewport: viewport) else { return nil }
        print("BEAR_AUDIT_SCROLL \(label) attempt=\(attempt) frame=\(frame) target=\(viewport)")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func coordinate(_ point: CGPoint) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: point.x - screen.minX, dy: point.y - screen.minY))
        }
        // 即使下一次定位失败，滚动也已改变全屏像素；必须作废此前截图缓存。
        didScroll()
        coordinate(drag.start).press(forDuration: 0.01, thenDragTo: coordinate(drag.end),
                                     withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    return nil
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

    func testFixedNavigationTitleIsSampledInPlaceWithoutAcceptingOccludedBodyText() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let bar = CGRect(x: 0, y: 62, width: 402, height: 44)
        let title = CGRect(x: 175, y: 74, width: 51, height: 21)
        XCTAssertNotNil(fixedChromeViewport(frame: title, screen: screen, navigationBar: bar,
                                            isNavigationElement: true))
        XCTAssertNil(fixedChromeViewport(frame: title, screen: screen, navigationBar: bar,
                                         isNavigationElement: false), "正文即使滚到同一位置也不能冒充导航标题")
        XCTAssertNil(fixedChromeViewport(frame: CGRect(x: 32, y: 128, width: 102, height: 16),
                                         screen: screen, navigationBar: bar, isNavigationElement: true))
        XCTAssertNil(fixedChromeViewport(frame: CGRect(x: 175, y: 99, width: 51, height: 21),
                                         screen: screen, navigationBar: bar, isNavigationElement: true))
        XCTAssertNil(fixedChromeViewport(frame: CGRect(x: -2, y: 74, width: 51, height: 21),
                                         screen: screen, navigationBar: bar, isNavigationElement: true))
    }

    func testContrastRevealDragIsBoundedAndKeepsTheSameUnobscuredViewportRequirement() throws {
        let viewport = CGRect(x: 0, y: 150, width: 402, height: 690)
        let above = try XCTUnwrap(contrastRevealDrag(frame: CGRect(x: 57, y: 103, width: 48, height: 15),
                                                     viewport: viewport))
        XCTAssertEqual(above.start.x, 8, "避开图表的中部手势区域")
        XCTAssertEqual(above.end.y - above.start.y, 71, accuracy: 0.1, "仅补足 47pt 遮挡与24pt留白，不整屏反甩")
        let below = try XCTUnwrap(contrastRevealDrag(frame: CGRect(x: 32, y: 850, width: 90, height: 15),
                                                     viewport: viewport))
        XCTAssertLessThan(below.end.y, below.start.y)
        let distant = try XCTUnwrap(contrastRevealDrag(frame: CGRect(x: 32, y: -600, width: 90, height: 15),
                                                       viewport: viewport))
        XCTAssertLessThanOrEqual(abs(distant.end.y - distant.start.y), viewport.height / 3)
        for drag in [above, below, distant] {
            XCTAssertTrue(viewport.contains(drag.start))
            XCTAssertTrue(viewport.contains(drag.end))
        }
        XCTAssertNil(contrastRevealDrag(frame: CGRect(x: 32, y: 250, width: 90, height: 15), viewport: viewport))
    }

    func testContrastRebindingDistinguishesSameNamedColumnsWithoutGuessingVerticalPosition() {
        let original = CGRect(x: 54.98, y: 66.67, width: 35, height: 14.33)
        let leftAfterScroll = original.offsetBy(dx: 0, dy: 117)
        let rightAfterScroll = original.offsetBy(dx: 176, dy: 117)
        XCTAssertTrue(sameContrastTextSlot(leftAfterScroll, original: original))
        XCTAssertFalse(sameContrastTextSlot(rightAfterScroll, original: original))
        XCTAssertFalse(sameContrastTextSlot(CGRect(x: 54.98, y: 200, width: 50, height: 20),
                                             original: original))
        let distinctColumns = [leftAfterScroll, rightAfterScroll].filter {
            sameContrastTextSlot($0, original: original)
        }
        XCTAssertEqual(distinctColumns.count, 1)
        let ambiguousRows = [leftAfterScroll, leftAfterScroll.offsetBy(dx: 0, dy: 90)].filter {
            sameContrastTextSlot($0, original: original)
        }
        XCTAssertEqual(ambiguousRows.count, 2, "同槽位重复不能挑最近的字框当成原元素")
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
        // 原生导航标题的 UIColor.label 是纯黑/白，也必须按实际像素通过 4.5:1。
        let nativeTitle = try XCTUnwrap(RenderedContrast.measure(image(ink: .black, background: .white), rect: rect, screen: rect))
        XCTAssertGreaterThan(nativeTitle.ratio, 4.5)
        let nativeDarkTitle = try XCTUnwrap(RenderedContrast.measure(image(ink: .white, background: .black), rect: rect, screen: rect))
        XCTAssertGreaterThan(nativeDarkTitle.ratio, 4.5)
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
    // 与 BearTheme 和原生导航 label 一致；不把图表系列色当文字墨色。
    static let inks: [[Int]] = [
        [0, 0, 0], [255, 255, 255],
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
