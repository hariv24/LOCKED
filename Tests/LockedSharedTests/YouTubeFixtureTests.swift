import XCTest
@testable import LockedShared

/// Runs the shared fixture `ChromeExtension/tests/youtube-url-cases.json` (also used by the
/// extension's `youtube-url.test.mjs`) against `YouTubeURL.videoId(from:)`, so the Swift parser the
/// app uses when the user pastes a link and the JS port in `allowlist.js` can't drift apart.
final class YouTubeFixtureTests: XCTestCase {
    struct Case: Decodable {
        let input: String
        let expected: String?
        let note: String?
        /// Newer Foundation (swift-foundation, macOS 14+ RFC 3986 parsing) percent-encodes some
        /// characters that older `URLComponents(string:)` rejected, so it may return this instead.
        /// Harmless: the extension enforces on WHATWG-parsed URLs and accepts these too.
        let swiftLenient: String?
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // LockedSharedTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("ChromeExtension/tests/youtube-url-cases.json")
    }

    func testSharedFixtureMatchesSwiftParser() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let got = YouTubeURL.videoId(from: c.input)
            if let lenient = c.swiftLenient, got == lenient { continue }
            XCTAssertEqual(got, c.expected, "input: \(c.input.debugDescription) \(c.note ?? "")")
        }
    }
}
