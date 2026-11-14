import XCTest
@testable import BaseballStatTracker

/// The legal links must keep working once the GitHub repository is private
/// (owner, 2026-11-13): they live on the website, not on github.com.
final class LegalLinksTests: XCTestCase {
    func testPrivacyPolicyIsThePublishedPage() {
        XCTAssertEqual(LegalLinks.privacyPolicy.absoluteString, "https://divinedavis.com/barrel/privacy/")
    }

    func testSupportIsThePublishedPage() {
        XCTAssertEqual(LegalLinks.support.absoluteString, "https://divinedavis.com/barrel/support/")
    }

    func testNoLegalLinkPointsAtGitHub() {
        for url in [LegalLinks.privacyPolicy, LegalLinks.support, LegalLinks.termsOfUse] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertFalse((url.host ?? "").contains("github"), url.absoluteString)
        }
    }
}
