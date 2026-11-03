import XCTest

final class BootstrapUITests: XCTestCase {
    @MainActor
    func testWarmLightHomeAndProviderNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
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
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["open-signing-verification"].tap()
        XCTAssertTrue(app.buttons["write-probe"].waitForExistence(timeout: 5))
        attach(app, name: "signing-dark")
    }

    @MainActor
    func testDevelopmentFeatureRegistersWithoutAICoreChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--counter-proof"]
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
