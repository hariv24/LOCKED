import XCTest
import LockedShared
@testable import LockedBridgeCore

final class BridgeControllerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_793_880_000)

    var session: SessionState?
    var now: Date!
    var sent: [StateMessage] = []
    var heartbeats: [BridgeHeartbeat] = []
    var controller: BridgeController!

    override func setUp() {
        super.setUp()
        now = start
        session = nil
        sent = []
        heartbeats = []
        controller = BridgeController(
            loadSession: { [unowned self] in self.session },
            writeHeartbeat: { [unowned self] in self.heartbeats.append($0) },
            send: { [unowned self] in self.sent.append($0) },
            now: { [unowned self] in self.now }
        )
    }

    func makeSession(minutes: Double = 30, sites: [String] = ["https://claude.ai"]) -> SessionState {
        SessionState(startedAt: start, endsAt: start.addingTimeInterval(minutes * 60),
                     allowlist: Allowlist(websites: sites.map { WebsiteEntry(url: $0, scope: .domain) }))
    }

    func testNoPushBeforeHello() {
        session = makeSession()
        controller.poll()
        controller.poll()
        XCTAssertTrue(sent.isEmpty)
    }

    func testHelloSendsStateAndHeartbeat() {
        session = makeSession()
        controller.handle(.hello(version: "0.1.0"))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].active, true)
        XCTAssertEqual(heartbeats.last?.extensionVersion, "0.1.0")
        XCTAssertEqual(heartbeats.last?.lastSeen, start)
        XCTAssertEqual(controller.extensionVersion, "0.1.0")
    }

    func testHelloWithoutSessionSendsInactive() {
        controller.handle(.hello(version: nil))
        XCTAssertEqual(sent, [.inactive])
    }

    func testRepeatedHelloAlwaysResends() {
        controller.handle(.hello(version: "1"))
        controller.handle(.hello(version: "1"))
        XCTAssertEqual(sent.count, 2)
    }

    func testPollOnlyPushesOnChange() {
        session = makeSession()
        controller.handle(.hello(version: "1"))
        for _ in 0..<5 {
            now = now.addingTimeInterval(1)
            controller.poll()
        }
        XCTAssertEqual(sent.count, 1, "unchanged session must not be re-sent")

        session = makeSession(sites: ["https://claude.ai", "https://chatgpt.com"])
        controller.poll()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[1].websites?.count, 2)

        controller.poll()
        XCTAssertEqual(sent.count, 2)
    }

    func testIrrelevantChangesDoNotPush() {
        var s = makeSession()
        session = s
        controller.handle(.hello(version: "1"))
        s.allowlist.apps.append(AllowedApp(bundleId: "com.apple.Notes", name: "Notes"))
        s.allowlist.pdfs.append(PDFEntry(path: "/a.pdf"))
        session = s
        controller.poll()
        XCTAssertEqual(sent.count, 1, "the extension doesn't see apps/pdfs")
    }

    func testExtendedSessionPushes() {
        session = makeSession(minutes: 30)
        controller.handle(.hello(version: "1"))
        session = makeSession(minutes: 60)
        controller.poll()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[1].endsAt, start.addingTimeInterval(3600))
    }

    func testExpiryPushesInactiveOnce() {
        session = makeSession(minutes: 1)
        controller.handle(.hello(version: "1"))
        now = start.addingTimeInterval(59)
        controller.poll()
        XCTAssertEqual(sent.count, 1)
        now = start.addingTimeInterval(60)
        controller.poll()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[1], .inactive)
        now = start.addingTimeInterval(61)
        controller.poll()
        XCTAssertEqual(sent.count, 2)
    }

    func testSessionDeletedPushesInactive() {
        session = makeSession()
        controller.handle(.hello(version: "1"))
        session = nil
        controller.poll()
        XCTAssertEqual(sent.last, .inactive)
        XCTAssertEqual(sent.count, 2)
    }

    func testNewSessionAfterInactivePushesActive() {
        controller.handle(.hello(version: "1"))
        session = makeSession()
        controller.poll()
        XCTAssertEqual(sent.map(\.active), [false, true])
    }

    func testPingRefreshesHeartbeatWithoutResending() {
        controller.handle(.hello(version: "2"))
        let before = heartbeats.count
        now = start.addingTimeInterval(20)
        controller.handle(.ping)
        XCTAssertEqual(heartbeats.count, before + 1)
        XCTAssertEqual(heartbeats.last?.lastSeen, start.addingTimeInterval(20))
        XCTAssertEqual(heartbeats.last?.extensionVersion, "2")
        XCTAssertEqual(sent.count, 1)
    }

    func testPingBeforeHelloSyncsState() {
        controller.handle(.ping)
        XCTAssertEqual(sent, [.inactive])
        controller.handle(.ping)
        XCTAssertEqual(sent.count, 1)
    }

    func testUnknownMessageIgnored() {
        controller.handle(.unknown(type: "x"))
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(heartbeats.isEmpty)
    }

    func testHeartbeatTick() {
        controller.heartbeat()
        now = start.addingTimeInterval(2)
        controller.heartbeat()
        XCTAssertEqual(heartbeats.map(\.lastSeen), [start, start.addingTimeInterval(2)])
        XCTAssertNil(heartbeats[0].extensionVersion)
    }
}
