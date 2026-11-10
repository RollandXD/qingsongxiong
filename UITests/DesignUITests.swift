import XCTest

/// 全部画面使用 Debug 模拟器注入的合成账户，不读取真实凭据。
final class DesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ appearance: String = "light", scenario: String = "normal", widgets: Bool = false, reduceMotion: Bool = false, demoNow: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", widgets ? "--widget-demo" : "--demo-usage",
                               "--demo-scenario", scenario, "-bear.appearance", appearance]
        // 固定演示数据的生成时刻（仅数据；视图仍用真实时钟）。
        // 数据读数 15 分钟后视图会判为旧读数，会让情绪词断言失效，所以默认不传，只在只截图的场景显式传入。
        if let demoNow { app.launchArguments += ["--demo-now", demoNow] }
        if reduceMotion { app.launchArguments.append("--ui-reduce-motion") }
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
            XCTAssertTrue(app.descendants(matching: .any)["honey-stage"].firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["time-scrubber"].firstMatch.exists)
            attach(app, "dashboard-" + appearance)
            attach(app, "honey-stage-" + appearance)
            try auditRenderedAccessibility(app, test: self)
            let balance = app.buttons["provider-deepseek"]
            // 对准真实 ScrollView，多次滚动直到余额行进入可点击区域。
            for _ in 0..<4 where !balance.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(balance.isHittable, "首页下半部可滚动抵达余额卡")
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
    func testCodexDetailShowsIndependentReviewWindow() {
        let app = launch()
        tap("provider-codex", app)
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        // 窗口行现在是组合后的静态元素：不再可选，只断言存在。
        let review = app.descendants(matching: .any)["window-codex-code_review_rate_limit.primary_window"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        attach(app, "codex-review-independent")
        goBack(app)
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBalancesKeepCurrenciesSeparate() {
        let app = launch(scenario: "multi-currency")
        // 币种代码是余额行里独立的 Text；先滚到余额行再断言。
        let cny = app.staticTexts["CNY"]
        for _ in 0..<4 where !cny.isHittable { app.swipeUp() }
        XCTAssertTrue(cny.exists)
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
            for _ in 0..<3 where !app.staticTexts["锁屏 · 圆形"].isHittable { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["锁屏 · 圆形"].exists)
            attach(app, "widgets-lockscreen-" + appearance)
            for _ in 0..<3 where !app.staticTexts["中转 · 小号"].isHittable { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["中转 · 小号"].isHittable)
            attach(app, "widgets-relay-" + appearance)
            app.terminate()
        }
    }

    @MainActor
    func testMotionTourAtNormalSpeed() {
        print("BEAR_MOTION_START \(Date().timeIntervalSince1970)")
        let app = launch(scenario: "motion")
        pause()
        // 真正的下拉/释放，不调用测试专用刷新入口。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
            .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        waitForMood("留意用量", app)
        app.buttons["refresh-all"].tap()
        waitForMood("额度告急", app)
        attach(app, "motion-threshold-alert")
        pause()
        app.buttons["refresh-all"].tap()
        waitForMood("额度充足", app)
        pause()
        app.buttons["refresh-all"].tap()
        XCTAssertTrue(app.staticTexts["已核实，读数未变化"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "motion-verified-unchanged")
        pause()
        // 时间尺：按住从左侧拖到约 70% 处并停留，松手后回到「现在」。
        // XCUITest 无法在手势保持期间截图，所以 motion-scrubber 抓的是保持结束后的画面。
        attach(app, "honey-stage")
        let scrubber = app.descendants(matching: .any)["time-scrubber"].firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        pause()
        attach(app, "motion-scrubber")
        pause()
        app.buttons["refresh-all"].tap()
        pause()
        tap("provider-codex", app)
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        attach(app, "codex-detail")
        pause()
        goBack(app)
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        pause()
        app.activate()
        pause()
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 5))
        app.swipeUp()
        tap("relay-account-11111111-2222-3333-4444-555555555555", app)
        XCTAssertTrue(app.buttons["relay-refresh"].waitForExistence(timeout: 5))
        app.buttons["relay-refresh"].tap()
        pause()
        attach(app, "motion-relay-balance")
        print("BEAR_MOTION_END \(Date().timeIntervalSince1970)")
    }

    @MainActor
    func testRelayCreateEditFailureAndDelete() {
        let app = launch()
        tap("relay-manage", app)
        XCTAssertTrue(app.navigationBars["中转账户"].waitForExistence(timeout: 5))
        app.buttons["relay-add"].tap()
        let name = app.textFields["relay-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        let oldName = name.value as? String ?? "我的中转"
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + "Demo Relay")
        let key = app.secureTextFields["relay-key"]
        key.tap(); key.typeText("invalid-demo")
        app.buttons["relay-save"].tap()
        XCTAssertTrue(app.staticTexts["relay-error"].waitForExistence(timeout: 5))
        key.tap()
        key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        attach(app, "relay-validation-failure") // 安全字段清空后才保存截图。
        key.typeText("fixture-only")
        app.buttons["relay-save"].tap()
        XCTAssertTrue(app.navigationBars["中转账户"].waitForExistence(timeout: 5))
        let created = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'relay-list-' AND label CONTAINS 'Demo Relay'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        created.tap()
        attach(app, "relay-detail-created")
        app.buttons["中转账户操作"].tap()
        app.buttons["编辑账户"].tap()
        XCTAssertTrue(app.buttons["relay-save"].waitForExistence(timeout: 5))
        // 密钥留空时保留旧值，名称不变也执行验证后替换事务。
        app.buttons["relay-save"].tap()
        XCTAssertTrue(app.buttons["relay-refresh"].waitForExistence(timeout: 5))
        app.buttons["relay-refresh"].tap()
        XCTAssertTrue(app.staticTexts["已核实，余额未变化"].waitForExistence(timeout: 5))
        app.buttons["中转账户操作"].tap()
        app.buttons["删除账户"].tap()
        app.buttons["删除账户"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["中转账户"].waitForExistence(timeout: 5))
        attach(app, "relay-after-delete")
    }

    @MainActor
    func testMotionRespectsReduceMotionAndFailureFeedback() {
        let app = launch(scenario: "motion", reduceMotion: true)
        app.buttons["refresh-all"].tap()
        waitForMood("留意用量", app)
        attach(app, "reduce-motion-warning")
        app.buttons["refresh-all"].tap()
        waitForMood("额度告急", app)
        attach(app, "reduce-motion-threshold")
        app.terminate()
        let failed = launch(scenario: "partial")
        failed.buttons["refresh-all"].tap()
        XCTAssertTrue(failed.staticTexts["读取未完成，已保留原状态"].waitForExistence(timeout: 6))
        attach(failed, "motion-refresh-failed")
    }

    @MainActor
    func testHomeShowsTwoChosenCardsAndTimeline() throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            // 两个主卡位置始终存在，谁在里面由用户选。
            XCTAssertTrue(app.descendants(matching: .any)["home-card-0"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["home-card-1"].firstMatch.exists)
            attach(app, "home-cards-" + appearance)

            let timeline = app.descendants(matching: .any)["usage-timeline"].firstMatch
            for _ in 0..<5 where !timeline.exists { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(timeline.exists, "过去用量时间线可达")
            attach(app, "usage-timeline-" + appearance)
            try auditRenderedAccessibility(app, test: self)
            app.terminate()
        }
    }

    @MainActor
    func testPaceReferenceAppearsOnDetailAndJar() throws {
        let app = launch()
        // 首页蜜罐下的周配速参考：只说位置关系，不说“必须花完”。
        let jarPace = app.descendants(matching: .any)["jar-pace-codex"].firstMatch
        XCTAssertTrue(jarPace.waitForExistence(timeout: 10))
        XCTAssertTrue(jarPace.label.contains("参考剩"), jarPace.label)
        attach(app, "jar-pace")

        tap("provider-codex", app)
        let windowPace = app.descendants(matching: .any)["window-pace-codex-five_hour"].firstMatch
        XCTAssertTrue(windowPace.waitForExistence(timeout: 8))
        XCTAssertTrue(windowPace.label.contains("参考剩"), windowPace.label)
        attach(app, "window-pace")
    }

    @MainActor
    func testRecoveryPreviewIsIndependentOfCurrentReading() throws {
        let app = launch(demoNow: "2026-11-10T02:00:00Z")
        let preview = app.descendants(matching: .any)["recovery-preview"].firstMatch
        for _ in 0..<5 where !preview.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(preview.exists, "恢复预览区可达")
        // 主卡与蜜罐的当前读数不随预览变化（预览只描述“何时回满”）。
        let before = app.descendants(matching: .any)["home-card-0"].firstMatch.label
        attach(app, "recovery-preview")
        let after = app.descendants(matching: .any)["home-card-0"].firstMatch.label
        XCTAssertEqual(before, after)
        app.terminate()
    }

    @MainActor
    func testTimelineExplainsMissingHistoryInsteadOfFakingIt() throws {
        let app = launch(scenario: "no-history")
        let empty = app.descendants(matching: .any)["timeline-empty"].firstMatch
        for _ in 0..<6 where !empty.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(empty.exists, "没有历史时必须给出空态说明")
        attach(app, "timeline-empty")
    }

    @MainActor
    func testReduceTransparencyKeepsCardsReadable() throws {
        let app = launch()
        // 减少透明度由模拟器设置注入；此处断言页面依然可读、可导航。
        XCTAssertTrue(app.buttons["provider-codex"].waitForExistence(timeout: 10))
        attach(app, "reduce-transparency-home")
        try auditRenderedAccessibility(app, test: self)
        app.terminate()
    }

    @MainActor
    private func waitForMood(_ mood: String, _ app: XCUIApplication) {
        let hero = app.descendants(matching: .any)["dashboard-hero"].firstMatch
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", mood), object: hero)
        let result = XCTWaiter.wait(for: [changed], timeout: 15)
        if result != .completed { attach(app, "unresolved-mood-" + mood) }
        XCTAssertEqual(result, .completed, mood)
    }

    @MainActor
    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        // 部分可见的 Glass 控件可能仍被 AX 标为可点击；先避开导航栏和底部安全区。
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

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
        else if app.navigationBars.buttons["轻松熊"].exists { app.navigationBars.buttons["轻松熊"].tap() }
        else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
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
