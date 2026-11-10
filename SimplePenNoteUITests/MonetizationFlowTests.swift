import XCTest

@MainActor
final class MonetizationFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPageLimitExplainsUpgradeAndAllowsDismissal() {
        let app = launch(screen: "sidebar")
        let newNote = button(containing: "새 노트 만들기", in: app)
        XCTAssertTrue(newNote.waitForExistence(timeout: 10))
        newNote.tap()

        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "무료 페이지 5장을 모두 사용했습니다", in: app).exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        app.buttons["paywall.close"].tap()

        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["나의 노트"].exists)
    }

    func testFreeBatchExportShowsRelevantBenefit() {
        let app = launch(screen: "sidebar")
        let batchExport = button(containing: "PDF로 묶기", in: app)
        XCTAssertTrue(batchExport.waitForExistence(timeout: 10))
        batchExport.tap()

        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "여러 장의 기록을", in: app).exists)
        XCTAssertTrue(text(containing: "하나의 PDF로", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(batchExport.waitForExistence(timeout: 5))
    }

    func testFreeExportOffersBothFormatsAndCleanExportUpgrade() {
        let app = launch(screen: "export")
        let pdf = app.buttons["PDF 문서로 공유"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["PNG 이미지로 공유"].exists)
        XCTAssertTrue(text(containing: "무료 내보내기에는 SimplePenNote 워터마크", in: app).exists)

        let cleanExport = button(containing: "워터마크 없이 내보내기", in: app)
        if !cleanExport.isHittable { app.swipeUp() }
        XCTAssertTrue(cleanExport.waitForExistence(timeout: 5))
        cleanExport.tap()

        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "내 필기만 담아", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.buttons["현재 노트 내보내기"].waitForExistence(timeout: 5))
    }

    func testTemplateGalleryShowsSixFreeStylesAndCanBeClosed() {
        let app = launch(screen: "templates")
        XCTAssertTrue(app.navigationBars["새 노트"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "모든 템플릿은 무료입니다", in: app).exists)
        for name in ["무지", "모눈", "줄글", "코넬 노트", "위클리", "오답 노트"] {
            let template = button(containing: name, in: app)
            if !template.exists { app.swipeUp() }
            XCTAssertTrue(template.exists, "Missing template: \(name)")
        }
        app.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["현재 노트 내보내기"].waitForExistence(timeout: 5))
    }

    private func launch(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Demo data is isolated from real notes and starts with five active pages.
        app.launchArguments = ["-DemoMode", "1", "-OpenScreen", screen, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        return app
    }

    private func button(containing label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func text(containing label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
}
