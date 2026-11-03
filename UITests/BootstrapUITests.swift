import XCTest

final class BootstrapUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testWarmLightHomeAndProviderNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-bear.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 10))
        attach(app, name: "home-light")
        app.buttons["provider-codex"].tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        attach(app, name: "provider-gated")
    }

    @MainActor
    func testSigningVerificationScreenAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-bear.appearance", "dark"]
        app.launch()
        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        app.buttons["open-signing-verification"].tap()
        XCTAssertTrue(app.buttons["write-probe"].waitForExistence(timeout: 5))
        attach(app, name: "signing-dark")
    }

    @MainActor
    func testDeepSeekConnectionUsesSecureEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-bear.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["provider-deepseek"].waitForExistence(timeout: 10))
        app.buttons["provider-deepseek"].tap()
        app.buttons["connect-deepseek"].tap()
        XCTAssertTrue(app.secureTextFields["deepseek-api-key"].waitForExistence(timeout: 5))
        attach(app, name: "deepseek-secure-entry-empty")
    }

    @MainActor
    func testHomeAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-bear.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped, .contrast])
    }

    @MainActor
    func testLargeTypeKeepsProviderConnectionReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-large-type", "-bear.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 10))
        attach(app, name: "home-accessibility3-dark")
        let provider = app.buttons["provider-deepseek"]
        for _ in 0..<4 where !provider.isHittable { app.swipeUp() }
        provider.tap()
        let connect = app.buttons["connect-deepseek"]
        for _ in 0..<4 where !connect.isHittable { app.swipeUp() }
        XCTAssertTrue(connect.isHittable)
        attach(app, name: "deepseek-accessibility3-dark")
    }

    @MainActor
    func testPrivacyClearsFeatureDataAndReportsCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-bear.appearance", "light"]
        app.launch()
        app.buttons["设置"].tap()
        app.buttons["open-privacy"].tap()
        let clear = app.buttons["clear-feature-data"]
        if !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["清除功能数据"].tap()
        let result = app.staticTexts["clear-data-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "功能凭据与额度缓存已清除。")
        attach(app, name: "privacy-cleared-demo")
    }

    @MainActor
    func testDevelopmentFeatureRegistersWithoutAICoreChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--counter-proof"]
        app.launch()
        app.buttons["计数验证"].tap()
        let increment = app.buttons["counter-increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        increment.tap()
        XCTAssertEqual(app.staticTexts["counter-value"].label, "1")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
