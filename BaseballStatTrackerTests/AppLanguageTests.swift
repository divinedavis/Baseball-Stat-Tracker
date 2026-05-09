import XCTest
@testable import BaseballStatTracker

final class AppLanguageTests: XCTestCase {
    func testToggledFlipsBetweenEnAndEs() {
        XCTAssertEqual(AppLanguage.en.toggled(), .es)
        XCTAssertEqual(AppLanguage.es.toggled(), .en)
    }

    func testDisplayCodeIsUppercased() {
        XCTAssertEqual(AppLanguage.en.displayCode, "EN")
        XCTAssertEqual(AppLanguage.es.displayCode, "ES")
    }

    func testLocaleMatchesIdentifier() {
        XCTAssertEqual(AppLanguage.en.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.es.locale.identifier, "es")
    }

    func testRawValueRoundTrip() {
        for lang in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage(rawValue: lang.rawValue), lang)
        }
    }
}

final class AppearanceModeTests: XCTestCase {
    func testColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testRawValueRoundTrip() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(rawValue: mode.rawValue), mode)
        }
    }
}
