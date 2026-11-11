import XCTest

/// End-to-end checks for the 1.3 features: localized UI, Pro selection → transparent PNG →
/// handwriting library → insertion, and the wide-screen (iPad / unfolded Duo) layout.
@MainActor
final class CoreFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Localization

    func testEveryStoreLanguageShowsTranslatedMainScreens() {
        let expected: [(lang: String, locale: String, myNotes: String, newNote: String, settings: String)] = [
            ("en", "en_US", "My Notes", "New Note", "Settings"),
            ("ja", "ja_JP", "マイノート", "新規ノートを作成", "設定"),
            ("zh-Hans", "zh_CN", "我的笔记", "新建笔记", "设置"),
        ]
        for item in expected {
            let app = launch(screen: "sidebar", language: item.lang, locale: item.locale)
            XCTAssertTrue(app.staticTexts[item.myNotes].waitForExistence(timeout: 10), "\(item.lang): library title")
            XCTAssertTrue(button(containing: item.newNote, in: app).exists, "\(item.lang): new note button")
            assertNoHangul(in: app, item.lang)
            app.buttons[item.settings].tap()
            XCTAssertTrue(app.navigationBars[item.settings].waitForExistence(timeout: 5), "\(item.lang): settings")
            assertNoHangul(in: app, "\(item.lang) settings")
            app.terminate()
        }
    }

    func testPaywallIsTranslated() {
        let app = launch(screen: "paywall", language: "ja", locale: "ja_JP")
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "一度の購入でずっと使える", in: app).exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        assertNoHangul(in: app, "ja paywall")
    }

    // MARK: - Pro: selection → transparent PNG → library → insertion

    func testProSelectionExportsTransparentAndSavesToLibrary() {
        let app = launch(screen: "selectionPreset", pro: true)
        let preview = app.buttons["selection.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.isEnabled, "preset selection covers ink")
        preview.tap()

        XCTAssertTrue(app.navigationBars["선택 영역 내보내기"].waitForExistence(timeout: 5))
        let transparent = app.switches["export.transparent"]
        reveal(transparent, in: app)
        XCTAssertTrue(transparent.exists)
        // Tap the switch itself; tapping the row's center (its label) doesn't toggle on every OS.
        if transparent.value as? String != "1" { transparent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(transparent.value as? String, "1")
        XCTAssertFalse(app.buttons["paywall.close"].exists, "Pro must not see the paywall")

        let save = app.buttons["export.saveSnippet"]
        reveal(save, in: app)
        save.tap()
        let name = app.textFields["손글씨 이름"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UITest")
        // iPadOS presents this text-field alert without the Alert element type; find the button anywhere.
        let confirm = app.alerts.buttons["저장"].exists ? app.alerts.buttons["저장"]
            : app.buttons.matching(NSPredicate(format: "label == %@", "저장")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["export.snippetStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "보관함에 저장했습니다", in: app).exists)
    }

    func testInsertingFromLibraryAddsInkThatCanBeUndone() {
        let app = launch(screen: "snippets", pro: true)
        XCTAssertTrue(app.navigationBars["손글씨 보관함"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Pro로 손글씨 보관함 사용"].exists, "Pro sees the library, not the upsell")
        let insert = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "노트에 넣기")).firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        insert.tap()

        let commit = app.buttons["snippets.commitInsertion"]
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["canvas.placement"].exists || app.images["canvas.placement"].exists
                      || app.descendants(matching: .any)["canvas.placement"].exists)
        commit.tap()
        XCTAssertFalse(commit.waitForExistence(timeout: 2), "placement mode ends after inserting")

        let undo = app.buttons["실행 취소"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.buttons["필기 부분 선택"].isHittable, "canvas stays usable after undo")
    }

    // MARK: - Wide layout

    func testWideScreenDocksLibraryBesideCanvas() throws {
        let app = launch(screen: "sidebar")
        XCTAssertTrue(app.staticTexts["나의 노트"].waitForExistence(timeout: 10))
        guard app.windows.firstMatch.frame.width >= 700 else {
            throw XCTSkip("Narrow screen: the library is an overlay here.")
        }
        let export = app.buttons["현재 노트 내보내기"]
        XCTAssertTrue(export.isHittable, "canvas header stays usable while the library is open")
        XCTAssertFalse(app.buttons["노트 목록 닫기"].frame.intersects(export.frame))
        // Switching notes keeps the library docked.
        let journal = button(containing: "오늘의 일기", in: app)
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        XCTAssertTrue(app.staticTexts["오늘의 일기"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func launch(screen: String, pro: Bool = false, language: String = "ko", locale: String = "ko_KR") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "1", "-OpenScreen", screen, "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            + (pro ? ["-DemoPro"] : [])
        app.launch()
        return app
    }

    private func assertNoHangul(in app: XCUIApplication, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let hangul = try! NSRegularExpression(pattern: "[가-힣]")
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label) + app.buttons.allElementsBoundByIndex.map(\.label)
        let leftovers = labels.filter { hangul.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        XCTAssertTrue(leftovers.isEmpty, "\(context): untranslated \(leftovers)", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
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
