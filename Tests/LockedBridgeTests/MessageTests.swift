import XCTest
import LockedShared
@testable import LockedBridgeCore

final class MessageTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_793_880_000)  // 2026-11-05T12:00:00Z

    func session(endsIn seconds: TimeInterval = 3600) -> SessionState {
        SessionState(
            startedAt: start,
            endsAt: start.addingTimeInterval(seconds),
            allowlist: Allowlist(
                apps: [AllowedApp(bundleId: "com.apple.Notes", name: "Notes")],
                websites: [WebsiteEntry(url: "https://claude.ai", scope: .domain),
                           WebsiteEntry(url: "https://developer.apple.com/documentation/swiftui", scope: .page)],
                youtube: [YouTubeEntry(videoId: "dQw4w9WgXcQ", title: "x"),
                          YouTubeEntry(videoId: "a-b_c-d_e-f"),
                          YouTubeEntry(videoId: "dQw4w9WgXcQ")],
                pdfs: [PDFEntry(path: "/tmp/a.pdf")]
            )
        )
    }

    func json(_ m: StateMessage) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: m.encoded()) as? [String: Any])
    }

    // MARK: Incoming

    func testParseIncoming() {
        XCTAssertEqual(IncomingMessage.parse(Data(#"{"type":"hello","version":"0.1.0"}"#.utf8)), .hello(version: "0.1.0"))
        XCTAssertEqual(IncomingMessage.parse(Data(#"{"type":"hello"}"#.utf8)), .hello(version: nil))
        XCTAssertEqual(IncomingMessage.parse(Data(#"{"type":"ping"}"#.utf8)), .ping)
        XCTAssertEqual(IncomingMessage.parse(Data(#"{"type":"bogus","x":1}"#.utf8)), .unknown(type: "bogus"))
        XCTAssertEqual(IncomingMessage.parse(Data(#"{"version":"1"}"#.utf8)), .unknown(type: nil))
        XCTAssertNil(IncomingMessage.parse(Data("not json".utf8)))
        XCTAssertNil(IncomingMessage.parse(Data("[1,2]".utf8)))
        XCTAssertNil(IncomingMessage.parse(Data()))
    }

    func testHelloVersionIsCapped() throws {
        let long = String(repeating: "9", count: 10_000)
        let payload = try JSONSerialization.data(withJSONObject: ["type": "hello", "version": long])
        XCTAssertEqual(IncomingMessage.parse(payload),
                       .hello(version: String(repeating: "9", count: IncomingMessage.maxVersionLength)))
    }

    // MARK: State

    func testInactiveWhenNoSession() throws {
        let m = StateMessage(session: nil, now: start)
        XCTAssertEqual(m, .inactive)
        XCTAssertEqual(String(decoding: try m.encoded(), as: UTF8.self), #"{"active":false,"type":"state"}"#)
    }

    func testInactiveWhenExpired() throws {
        let s = session(endsIn: 60)
        XCTAssertEqual(StateMessage(session: s, now: s.endsAt), .inactive, "endsAt == now counts as expired")
        XCTAssertEqual(StateMessage(session: s, now: s.endsAt.addingTimeInterval(1)), .inactive)
        XCTAssertNotEqual(StateMessage(session: s, now: s.endsAt.addingTimeInterval(-1)), .inactive)
    }

    func testActiveStateJSON() throws {
        let obj = try json(StateMessage(session: session(), now: start))
        XCTAssertEqual(obj["type"] as? String, "state")
        XCTAssertEqual(obj["active"] as? Bool, true)
        XCTAssertEqual(obj["endsAt"] as? String, "2026-11-05T13:00:00Z")
        let websites = try XCTUnwrap(obj["websites"] as? [[String: Any]])
        XCTAssertEqual(websites.count, 2)
        XCTAssertEqual(websites[0]["url"] as? String, "https://claude.ai")
        XCTAssertEqual(websites[0]["scope"] as? String, "domain")
        XCTAssertEqual(websites[1]["url"] as? String, "https://developer.apple.com/documentation/swiftui")
        XCTAssertEqual(websites[1]["scope"] as? String, "page")
        XCTAssertEqual(Set(websites[0].keys), ["url", "scope"], "no ids leak into the protocol")
        XCTAssertEqual(obj["youtubeVideoIds"] as? [String], ["dQw4w9WgXcQ", "a-b_c-d_e-f"], "deduped, order kept")
        XCTAssertEqual(Set(obj.keys), ["type", "active", "endsAt", "websites", "youtubeVideoIds"])
    }

    func testActiveStateWithEmptyLists() throws {
        let s = SessionState(startedAt: start, endsAt: start.addingTimeInterval(10), allowlist: Allowlist())
        let raw = String(decoding: try StateMessage(session: s, now: start).encoded(), as: UTF8.self)
        XCTAssertEqual(raw, #"{"active":true,"endsAt":"2026-11-05T12:00:10Z","type":"state","websites":[],"youtubeVideoIds":[]}"#)
    }

    func testURLSlashesNotEscaped() throws {
        let raw = String(decoding: try StateMessage(session: session(), now: start).encoded(), as: UTF8.self)
        XCTAssertTrue(raw.contains("https://claude.ai"), raw)
        XCTAssertFalse(raw.contains("\\/"), raw)
    }

    func testEncodedStateIsFramable() throws {
        let payload = try StateMessage(session: session(), now: start).encoded()
        let framed = try NativeMessaging.frame(payload)
        var dec = FrameDecoder()
        XCTAssertEqual(try dec.append(framed), [payload])
    }

    func testStateDecodesBack() throws {
        let m = StateMessage(session: session(), now: start)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(StateMessage.self, from: m.encoded()), m)
    }
}
