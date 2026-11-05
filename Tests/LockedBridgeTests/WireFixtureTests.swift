import XCTest
import LockedShared
@testable import LockedBridgeCore

/// Pins the exact bytes the bridge sends for a representative session to the shared fixture
/// `ChromeExtension/tests/bridge-state-fixture.json`. The extension's `wire-contract.test.mjs`
/// parses the same bytes with `normalizeState`/`isUrlAllowed`, so a change on either side of the
/// native messaging protocol breaks a test instead of silently failing open in Chrome.
final class WireFixtureTests: XCTestCase {
    struct Fixture: Decodable {
        let wire: String
        let inactiveWire: String
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // LockedBridgeTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("ChromeExtension/tests/bridge-state-fixture.json")
    }

    /// Entries in the shape `SetupModel.normalizeWebsite` stores them: domain scope is
    /// `scheme://host[:port]`, page scope keeps the user's text (https:// added if missing).
    static func session() -> SessionState {
        let start = Date(timeIntervalSince1970: 1_793_880_000)  // 2026-11-05T12:00:00Z
        return SessionState(
            startedAt: start,
            endsAt: start.addingTimeInterval(3600),
            allowlist: Allowlist(
                apps: [AllowedApp(bundleId: "com.apple.Notes", name: "Notes")],
                websites: [
                    WebsiteEntry(url: "https://claude.ai", scope: .domain),
                    WebsiteEntry(url: "http://localhost", scope: .domain),
                    WebsiteEntry(url: "https://www.example.org", scope: .domain),
                    WebsiteEntry(url: "https://developer.apple.com/documentation/swiftui", scope: .page),
                    WebsiteEntry(url: "https://Docs.Python.org/3/library/", scope: .page),
                    WebsiteEntry(url: "https://en.wikipedia.org/wiki/Deep_work?useskin=vector#History", scope: .page),
                ],
                youtube: [YouTubeEntry(videoId: "dQw4w9WgXcQ", title: "x"),
                          YouTubeEntry(videoId: "a-b_c-d_e-f"),
                          YouTubeEntry(videoId: "dQw4w9WgXcQ")],
                pdfs: [PDFEntry(path: "/tmp/a.pdf")]
            )
        )
    }

    func testActiveStateMatchesSharedFixture() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        let s = Self.session()
        let wire = String(decoding: try StateMessage(session: s, now: s.startedAt).encoded(), as: UTF8.self)
        XCTAssertEqual(wire, fixture.wire)
    }

    func testInactiveStateMatchesSharedFixture() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        let s = Self.session()
        let wire = String(decoding: try StateMessage(session: s, now: s.endsAt).encoded(), as: UTF8.self)
        XCTAssertEqual(wire, fixture.inactiveWire)
    }

    /// The fixture's session.json side: what the app writes must decode in the bridge.
    func testSessionFileRoundTripsThroughStore() throws {
        let session = Self.session()
        let data = try LockedStore.makeEncoder().encode(session)
        XCTAssertEqual(try LockedStore.makeDecoder().decode(SessionState.self, from: data), session)
    }
}
