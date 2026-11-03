import XCTest

/// 全部画面使用 Debug 模拟器注入的合成账户，不读取真实凭据。
final class DesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ appearance: String = "light", scenario: String = "normal", widgets: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", widgets ? "--widget-demo" : "--demo-usage",
                               "--demo-scenario", scenario, "-bear.appearance", appearance]
        app.launch()
        if !widgets { XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 10)) }
        return app
    }

    @MainActor
    func testConnectedOverviewLightAndDark() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            XCTAssertTrue(app.buttons["provider-deepseek"].isHittable, "常规字号下三家的主要指标应同屏")
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped, .contrast])
            attach(app, "dashboard-" + appearance)
            app.terminate()
        }
    }

    @MainActor
    func testWindowFocusAndSingleExpansion() {
        let app = launch()
        tap("expand-codex", app)
        let review = "window-codex-code_review_rate_limit.primary_window"
        tap(review, app)
        XCTAssertTrue(app.buttons[review].isSelected)
        attach(app, "codex-review-independent")
        tap("expand-claude", app)
        XCTAssertFalse(app.buttons[review].exists, "同一时间只展开一家")
        tap("window-claude-seven_day_sonnet", app)
        XCTAssertTrue(app.buttons["window-claude-seven_day_sonnet"].isSelected)
        attach(app, "claude-model-limit")
        tap("expand-claude", app)
        XCTAssertFalse(app.buttons["window-claude-seven_day_sonnet"].exists)
        // 快速反向操作最终归位，不积累动画任务。
        app.buttons["expand-claude"].tap(withNumberOfTaps: 2, numberOfTouches: 1)
        XCTAssertTrue(app.buttons["provider-claude"].exists)
    }

    @MainActor
    func testBalancesKeepCurrenciesSeparate() {
        let app = launch(scenario: "multi-currency")
        tap("expand-deepseek", app)
        XCTAssertTrue(app.staticTexts["CNY"].exists)
        XCTAssertTrue(app.staticTexts["USD"].exists)
        attach(app, "balance-multiple-currencies")
        tap("provider-deepseek", app)
        XCTAssertTrue(app.navigationBars["DeepSeek"].waitForExistence(timeout: 5))
        attach(app, "balance-detail")
    }

    @MainActor
    func testRefreshReportsPartialFailureAndKeepsNavigationWorking() {
        let app = launch(scenario: "partial")
        app.buttons["refresh-all"].tap()
        XCTAssertTrue(app.staticTexts["读取未完成，已保留原状态"].waitForExistence(timeout: 8))
        attach(app, "refresh-partial-failure")
        tap("provider-claude", app)
        XCTAssertTrue(app.navigationBars["Claude"].waitForExistence(timeout: 5))
        attach(app, "refresh-failure-detail")
    }

    @MainActor
    func testUnavailableAndOldReadings() {
        for scenario in ["stale", "exhausted", "missing", "reconnect"] {
            let app = launch("dark", scenario: scenario)
            attach(app, "state-" + scenario)
            app.terminate()
        }
    }

    @MainActor
    func testWidgetLayoutsLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance, widgets: true)
            XCTAssertTrue(app.staticTexts["总览 · 中号"].waitForExistence(timeout: 10))
            attach(app, "widgets-overview-" + appearance)
            app.swipeUp()
            attach(app, "widgets-single-" + appearance)
            app.swipeUp()
            attach(app, "widgets-balance-" + appearance)
            app.terminate()
        }
    }

    @MainActor
    func testMotionTourAtNormalSpeed() {
        let app = launch()
        print("BEAR_MOTION_START \(Date().timeIntervalSince1970)")
        pause()
        tap("expand-codex", app)
        pause()
        tap("window-codex-rate_limit.primary_window", app)
        pause()
        tap("window-codex-code_review_rate_limit.primary_window", app)
        pause()
        tap("expand-codex", app)
        tap("expand-claude", app)
        pause()
        app.segmentedControls["window-picker-claude"].swipeLeft()
        pause()
        tap("expand-claude", app)
        tap("expand-deepseek", app)
        pause()
        attach(app, "balance-composition-expanded")
        tap("expand-deepseek", app)
        app.buttons["refresh-all"].tap()
        pause()
        tap("provider-codex", app)
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        attach(app, "codex-detail")
        pause()
        app.navigationBars.buttons.firstMatch.tap()
        print("BEAR_MOTION_END \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.press(.home)
        pause()
        app.activate()
        pause()
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        if !button.isHittable {
            for _ in 0..<3 where !button.isHittable { app.swipeUp() }
            for _ in 0..<5 where !button.isHittable { app.swipeDown() }
        }
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }

    private func pause() { Thread.sleep(forTimeInterval: 0.9) }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
