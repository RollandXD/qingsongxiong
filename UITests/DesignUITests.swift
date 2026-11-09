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
    func testContrastTokenProbe() throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--contrast-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["纯黑白 Black white"].waitForExistence(timeout: 5))
        attach(app, "contrast-token-probe")
        try app.performAccessibilityAudit(for: [.contrast]) { issue in
            print("BEAR_CONTRAST_PROBE \(issue.compactDescription) element=\(issue.element?.label ?? "nil")")
            return false // 收集问题，不屏蔽审计。
        }
    }

    @MainActor
    func testConnectedOverviewLightAndDark() throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            XCTAssertTrue(app.otherElements["dashboard-hero"].exists || app.staticTexts["dashboard-hero"].exists)
            attach(app, "dashboard-" + appearance)
            try auditRenderedAccessibility(app, test: self)
            app.swipeUp()
            XCTAssertTrue(app.buttons["provider-deepseek"].isHittable, "首页下半部可滚动抵达余额卡")
            attach(app, "dashboard-balance-" + appearance)
            app.terminate()
        }
    }

    @MainActor
    func testProviderDetailsLightAndDark() throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        for appearance in ["light", "dark"] {
            for provider in ["codex", "claude", "deepseek"] {
                let app = launch(appearance)
                tap("provider-" + provider, app)
                let name = provider == "codex" ? "Codex" : provider == "claude" ? "Claude" : "DeepSeek"
                XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
                attach(app, "detail-" + provider + "-" + appearance)
                try auditRenderedAccessibility(app, test: self)
                app.swipeUp()
                attach(app, "detail-bottom-" + provider + "-" + appearance)
                if provider != "deepseek" { XCTAssertTrue(app.staticTexts["接下来的重置"].exists) }
                app.terminate()
            }
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
        waitUntilGone(app.buttons[review])
        tap("window-claude-seven_day_sonnet", app)
        XCTAssertTrue(app.buttons["window-claude-seven_day_sonnet"].isSelected)
        attach(app, "claude-model-limit")
        tap("expand-claude", app)
        waitUntilGone(app.buttons["window-claude-seven_day_sonnet"])
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
        if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
        else if app.navigationBars.buttons["轻松熊"].exists { app.navigationBars.buttons["轻松熊"].tap() }
        else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 5))
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
        // 部分可见的 Glass 控件可能仍被 AX 标为可点击；先避开导航和标签栏覆盖区。
        for _ in 0..<8 {
            let center = button.frame.midY
            if center < 125 { app.swipeDown() }
            else if center > app.frame.height - 110 { app.swipeUp() }
            else if button.isHittable { break }
            else { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }

    private func pause() { Thread.sleep(forTimeInterval: 0.9) }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
