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
            // 套件整体跑时机器更忙，数据落盘晚一点；用等待而不是裸 exists，避免用例顺序造成的假失败。
            let hero = app.descendants(matching: .any)["dashboard-hero"].firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 15))
            // 主卡整张是按钮，内部 children:.contain 的容器（旧 honey-stage）会被按钮吞掉；
            // 这里改验卡上真有的东西：两张可选主卡、每张都报出两只蜜罐（5 小时 + 本周）的读数。
            XCTAssertTrue(app.descendants(matching: .any)["home-cards"].firstMatch.waitForExistence(timeout: 15))
            let cardPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "home-card-")
            XCTAssertEqual(app.descendants(matching: .any).matching(cardPredicate).count, 2, "首页两张可选主卡")
            let codexCard = app.buttons["provider-codex"]
            XCTAssertTrue(codexCard.waitForExistence(timeout: 15))
            let readings = codexCard.value as? String ?? ""
            XCTAssertTrue(readings.contains("5 小时剩"), readings)
            XCTAssertTrue(readings.contains("本周剩"), readings)
            XCTAssertFalse(app.descendants(matching: .any)["time-scrubber"].firstMatch.exists,
                           "恢复预览默认收起，不挤占当前读数和历史时间线")
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
        tap("recovery-preview-toggle", app)
        let scrubber = app.descendants(matching: .any)["time-scrubber"].firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        for _ in 0..<4 where !onScreen(scrubber, in: app) { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(onScreen(scrubber, in: app))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        pause()
        attach(app, "motion-scrubber")
        tap("recovery-preview-toggle", app)
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

            // 不只验“有两格”：通过可见编辑入口真正把 Claude 换成中转，再放两张余额卡。
            let relayID = "11111111-2222-3333-4444-555555555555"
            openCardPicker(1, app)
            app.buttons["pick-relay:" + relayID].tap()
            let transfer = mainCardButton(1, identifier: "relay-" + relayID, app)
            XCTAssertTrue(transfer.waitForExistence(timeout: 5))
            let relayAmount = transfer.value as? String ?? ""
            XCTAssertTrue(relayAmount.contains("USD 12.35"), "主卡按两位小数显示金额，必须保留币种：" + relayAmount)
            attach(app, "home-relay-main-" + appearance)

            openCardPicker(0, app)
            app.buttons["pick-provider:deepseek"].tap()
            let money = mainCardButton(0, identifier: "provider-deepseek", app)
            XCTAssertTrue(money.waitForExistence(timeout: 5))
            let amount = money.value as? String ?? ""
            XCTAssertTrue(amount.contains("CNY"), amount)
            XCTAssertTrue(amount.contains("128.36"), amount)
            XCTAssertFalse(amount.contains("5 小时剩"), "DeepSeek 余额主卡不能伪装成额度蜜罐")
            XCTAssertTrue(mainCardButton(1, identifier: "relay-" + relayID, app).exists)
            attach(app, "home-balance-pair-" + appearance)
            try auditRenderedAccessibility(app, test: self)
            money.tap()
            XCTAssertTrue(app.navigationBars["DeepSeek"].waitForExistence(timeout: 5))
            goBack(app)

            // 空位可重新填充；交换后两个目标仍独立，不重复、不把删除当“零余额”。
            openCardPicker(0, app)
            app.buttons["home-card-remove"].tap()
            let empty = app.buttons["home-card-empty-0"]
            XCTAssertTrue(empty.waitForExistence(timeout: 5))
            attach(app, "home-empty-slot-" + appearance)
            empty.tap()
            app.buttons["pick-provider:claude"].tap()
            XCTAssertTrue(mainCardButton(0, identifier: "provider-claude", app).waitForExistence(timeout: 5))
            app.buttons["home-cards-edit"].tap()
            app.buttons["home-cards-swap"].tap()
            XCTAssertTrue(mainCardButton(0, identifier: "relay-" + relayID, app).waitForExistence(timeout: 5))
            XCTAssertTrue(mainCardButton(1, identifier: "provider-claude", app).exists)
            attach(app, "home-swapped-cards-" + appearance)

            let timeline = app.descendants(matching: .any)["usage-timeline"].firstMatch
            XCTAssertTrue(timeline.exists, "时间线存在")
            // exists 不够：ScrollView 里的 VStack 是即时渲染，没滚到也会返回 true，
            // 截图会拍到首屏。这里按“元素真的进了屏幕”滚动，才能真的验到时间线。
            for _ in 0..<6 where !onScreen(timeline, in: app) { app.swipeUp() }
            XCTAssertTrue(onScreen(timeline, in: app), "时间线滚动后进入屏幕")
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
        // 详情页整行被 children:.combine 合并，配速文案就在行的 label 里。
        let windowRow = app.descendants(matching: .any)["window-codex-rate_limit.primary_window"].firstMatch
        if !windowRow.waitForExistence(timeout: 10) {
            dumpElements(app, keywords: ["window-", "参考", "rate_limit"], label: "codex-window-row")
        }
        XCTAssertTrue(windowRow.exists)
        if !windowRow.label.contains("参考剩") {
            dumpElements(app, keywords: ["window-codex"], label: "codex-window-labels")
        }
        XCTAssertTrue(windowRow.label.contains("参考剩"), windowRow.label)
        attach(app, "window-pace")
    }

    @MainActor
    func testRecoveryPreviewIsIndependentOfCurrentReading() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            let card = app.buttons["provider-codex"]
            let before = card.value as? String
            let scrubber = app.descendants(matching: .any)["time-scrubber"].firstMatch
            XCTAssertFalse(scrubber.exists, "默认收起")
            tap("recovery-preview-toggle", app)
            XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
            for _ in 0..<4 where !onScreen(scrubber, in: app) { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(onScreen(scrubber, in: app))
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
                .press(forDuration: 0.1,
                       thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            XCTAssertEqual(before, card.value as? String, "真实拖动预览不改变主卡当前读数")
            attach(app, "recovery-preview-" + appearance)
            // 收起不是隐藏审计：展开态的文字也按同一原生/渲染门禁验收。
            try auditRenderedAccessibility(app, test: self)
            tap("recovery-preview-toggle", app)
            XCTAssertFalse(scrubber.exists, "可以收起，归还首屏空间")
            app.terminate()
        }
    }

    @MainActor
    func testOldRecoveryPreviewDoesNotInventRefill() {
        let app = launch("dark", scenario: "stale")
        tap("recovery-preview-toggle", app)
        let reading = app.descendants(matching: .any)["recovery-codex-rate_limit.primary_window"].firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertTrue(reading.label.contains("读数未确认，刷新后再预览"), reading.label)
        XCTAssertFalse(reading.label.contains("预计此时回满"), reading.label)
        attach(app, "recovery-old-reading")
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
    func testTimelineSwitchesAccountsCurrenciesRangesAndKeepsVerticalScroll() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            tap("timeline-account", app)
            let deepseek = app.buttons["timeline-account-provider-deepseek"]
            XCTAssertTrue(deepseek.waitForExistence(timeout: 5))
            deepseek.tap()
            let chart = app.descendants(matching: .any)["timeline-chart"].firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            XCTAssertTrue(chart.label.contains("CNY 余额"), chart.label)
            XCTAssertFalse(app.descendants(matching: .any)["timeline-pace-note"].firstMatch.exists,
                           "金额没有重置周期，不得画额度配速线")
            tap("timeline-metric", app)
            app.buttons["USD 余额"].tap()
            XCTAssertTrue(chart.label.contains("USD 余额"), chart.label)
            for title in ["7 天", "30 天", "24 小时"] {
                let button = app.segmentedControls["timeline-range"].buttons[title]
                XCTAssertTrue(button.exists)
                button.tap()
                XCTAssertTrue(chart.label.contains(title), chart.label)
            }
            tap("timeline-account", app)
            let relay = app.buttons["timeline-account-relay-11111111-2222-3333-4444-555555555555"]
            XCTAssertTrue(relay.waitForExistence(timeout: 5))
            relay.tap()
            XCTAssertTrue(chart.label.contains("USD 余额"), chart.label)
            // 菜单在图表上方：切完账户时图表可能仍在屏幕底部外面。
            // 必须先把完整图表滚进稳定视口，再从它的真实位置验证纵向手势。
            for _ in 0..<6 {
                let frame = chart.frame
                if frame.minY < 160 { app.scrollViews.firstMatch.swipeDown() }
                else if frame.maxY > app.frame.maxY - 40 { app.scrollViews.firstMatch.swipeUp() }
                else { break }
            }
            XCTAssertTrue(onScreen(chart, in: app), "先完整露出图表，不能向屏幕外坐标发手势")
            attach(app, "timeline-relay-" + appearance)
            let reading = app.descendants(matching: .any)["timeline-reading"].firstMatch
            let latest = reading.label
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertNotEqual(reading.label, latest, "横向拖动必须真正选到历史读数")
            attach(app, "timeline-selection-" + appearance)

            // 初始位置可能已经到页底，继续上滑本来就不会移动，不能据此断言手势被截走。
            // 先在图表内下滑验证滚动，并给反向上滑留出真实余量；两方向都保留位移门槛。
            let chosenReading = reading.label
            let beforeDown = chart.frame.minY
            chart.swipeDown()
            XCTAssertGreaterThan(chart.frame.minY, beforeDown + 10,
                                 "图表上的纵向下滑必须带动首页，不能被横向选点截走")
            XCTAssertEqual(reading.label, chosenReading, "纵向滚动不能偷偷改掉历史选点")
            let beforeUp = chart.frame.minY
            chart.swipeUp()
            XCTAssertLessThan(chart.frame.minY, beforeUp - 10,
                              "已有滚动余量时，图表上的纵向上滑也必须带动首页")
            XCTAssertEqual(reading.label, chosenReading, "反向纵向滚动也不能改掉历史选点")
            app.terminate()
        }
    }

    @MainActor
    func testTimelineReadFailureIsVisibleAndRetryDoesNotEraseCurrentReadings() {
        let app = launch(scenario: "history-error")
        let before = app.buttons["provider-codex"].value as? String
        let error = app.descendants(matching: .any)["timeline-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["timeline-empty"].firstMatch.exists,
                       "读文件失败不能冒充首次安装空态")
        tap("timeline-retry", app)
        XCTAssertTrue(error.exists)
        XCTAssertEqual(before, app.buttons["provider-codex"].value as? String)
        attach(app, "timeline-read-error")
        app.terminate()
    }

    @MainActor
    private func openCardPicker(_ slot: Int, _ app: XCUIApplication) {
        tap("home-cards-edit", app)
        let edit = app.buttons["home-card-edit-" + String(slot)]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["选择卡片"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func mainCardButton(_ slot: Int, identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home-card-" + String(slot)].firstMatch
            .descendants(matching: .button).matching(identifier: identifier).firstMatch
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

    /// 元素是否已真的落在屏幕里（ScrollView 的即时渲染会让 exists 提前为真）。
    private func onScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.height > 0, frame.width > 0 else { return false }
        return frame.minY >= app.frame.minY && frame.maxY <= app.frame.maxY
    }

    /// 断言找不到元素时把无障碍树里相关行打出来：一次就能看出是“没有这个元素”还是“名字/层级不对”。
    /// 首屏结构快照：只打前 60 行，足够看出首页到底渲染了什么，又不会把日志冲爆。
    private func dumpScaffold(_ app: XCUIApplication, label: String) {
        let lines = app.debugDescription.split(separator: "\n").map(String.init)
        print("BEAR_SCAFFOLD_START \(label) total=\(lines.count)")
        for line in lines.prefix(60) { print("BEAR_SCAFFOLD \(line.trimmingCharacters(in: .whitespaces))") }
        print("BEAR_SCAFFOLD_END \(label)")
    }
    private func dumpElements(_ app: XCUIApplication, keywords: [String], label: String) {
        let lines = app.debugDescription.split(separator: "\n").map(String.init)
        let hits = lines.filter { line in keywords.contains { line.localizedCaseInsensitiveContains($0) } }
        print("BEAR_TREE_START \(label) hits=\(hits.count)")
        for line in hits.prefix(40) { print("BEAR_TREE \(line.trimmingCharacters(in: .whitespaces))" ) }
        print("BEAR_TREE_END \(label)")
    }
}
