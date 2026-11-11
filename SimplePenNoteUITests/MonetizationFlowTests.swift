import XCTest

@MainActor
final class MonetizationFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPageLimitExplainsUpgradeAndAllowsDismissal() {
        let app = launch(screen: "sidebar")
        // The library's row ("새 노트 만들기, 5 / 5"), not the header's "바로 새 노트 만들기".
        let newNote = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "새 노트 만들기")).firstMatch
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
        XCTAssertTrue(app.navigationBars["내보내기"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "무료 내보내기에는 SimplePenNote 워터마크", in: app).exists)
        reveal(pdf, in: app)
        XCTAssertTrue(pdf.exists)
        let png = app.buttons["PNG 이미지로 공유"]
        XCTAssertTrue(png.exists)

        let cleanExport = button(containing: "워터마크 없이 내보내기", in: app)
        if !cleanExport.isHittable { app.swipeUp() }
        XCTAssertTrue(cleanExport.waitForExistence(timeout: 5))
        cleanExport.tap()

        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "내 필기만 담아", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.switches["export.crop"].waitForExistence(timeout: 5))
    }

    func testQuickNoteOpensWithoutTemplatePicker() {
        let app = launch(screen: "canvas", pageCount: 1)
        app.buttons["바로 새 노트 만들기"].tap()
        XCTAssertTrue(app.staticTexts["노트 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["새 노트"].exists)
        XCTAssertTrue(app.buttons["펜 설정 펼치기"].exists)
        app.buttons["펜 설정 펼치기"].tap()
        XCTAssertTrue(app.buttons["파란 펜"].waitForExistence(timeout: 5))
        app.buttons["파란 펜"].tap()
        app.buttons["펜 설정 접기"].tap()
        XCTAssertTrue(app.buttons["펜 설정 펼치기"].exists)
    }

    func testTransparentCopyShowsProAndReturnsToSelectedOptions() {
        let app = launch(screen: "export")
        let transparent = app.switches["export.transparent"]
        XCTAssertTrue(transparent.waitForExistence(timeout: 10))
        transparent.tap()
        let copy = app.buttons["export.copyTransparent"]
        if !copy.isHittable { app.swipeUp() }
        copy.tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "내 스케치만 쏙", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(transparent.waitForExistence(timeout: 5))
        XCTAssertEqual(transparent.value as? String, "1")
        XCTAssertEqual(app.switches["export.crop"].value as? String, "1")
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

    func testPartialSelectionStaysFreeAndSaveUpgradePreservesTheSelection() {
        let app = launch(screen: "selection")
        let allInk = app.buttons["전체 필기 선택"]
        XCTAssertTrue(allInk.waitForExistence(timeout: 10))
        allInk.tap()
        let preview = app.buttons["selection.preview"]
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        XCTAssertTrue(app.navigationBars["선택 영역 내보내기"].waitForExistence(timeout: 5))
        let png = app.buttons["PNG 이미지로 공유"]
        reveal(png, in: app)
        XCTAssertTrue(png.exists)
        XCTAssertFalse(app.buttons["paywall.close"].exists)
        XCTAssertFalse(app.switches["export.crop"].exists)
        let save = app.buttons["export.saveSnippet"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "계속 꺼내 쓰세요", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.navigationBars["선택 영역 내보내기"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["export.crop"].exists)
    }

    func testSnippetLibraryExplainsStorageAndReturnsAfterUpgradeDismissal() {
        let app = launch(screen: "snippets")
        XCTAssertTrue(app.navigationBars["손글씨 보관함"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "보관함은 이 기기에 저장됩니다", in: app).exists)
        let upgrade = app.buttons["Pro로 손글씨 보관함 사용"]
        upgrade.tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "계속 꺼내 쓰세요", in: app).exists)
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.navigationBars["손글씨 보관함"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["필기 부분 선택"].waitForExistence(timeout: 5))
    }

    private func launch(screen: String, pageCount: Int = 5) -> XCUIApplication {
        let app = XCUIApplication()
        // Demo data is isolated from real notes and starts with five active pages.
        app.launchArguments = ["-DemoMode", "1", "-OpenScreen", screen, "-DemoPageCount", String(pageCount), "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func button(containing label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func text(containing label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
}
