import XCTest
@testable import LockedShared

final class ModelTests: XCTestCase {
    /// 2026-11-05T12:00:00Z (whole seconds: ISO-8601 encoding drops fractional seconds).
    let start = Date(timeIntervalSince1970: 1_793_880_000)

    func makeAllowlist() -> Allowlist {
        Allowlist(
            apps: [AllowedApp(bundleId: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app"),
                   AllowedApp(bundleId: "com.microsoft.VSCode", name: "Code")],
            websites: [WebsiteEntry(url: "https://claude.ai", scope: .domain),
                       WebsiteEntry(url: "https://developer.apple.com/documentation/swiftui", scope: .page)],
            youtube: [YouTubeEntry(videoId: "dQw4w9WgXcQ", title: "Never"), YouTubeEntry(videoId: "a-b_c-d_e-f")],
            pdfs: [PDFEntry(path: "/Users/me/Papers/attention.pdf")]
        )
    }

    func makeSession() -> SessionState {
        SessionState(startedAt: start, endsAt: start.addingTimeInterval(3600), allowlist: makeAllowlist())
    }

    // MARK: Codable

    func testSessionRoundTripWithISODates() throws {
        let session = makeSession()
        let data = try LockedStore.makeEncoder().encode(session)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"startedAt\" : \"2026-11-05T12:00:00Z\""), json)
        XCTAssertTrue(json.contains("\"endsAt\" : \"2026-11-05T13:00:00Z\""), json)
        XCTAssertTrue(json.contains("\"version\" : 1"), json)
        XCTAssertTrue(json.contains("\"scope\" : \"domain\""), json)
        XCTAssertTrue(json.contains("\n"), "pretty printed")

        let decoded = try LockedStore.makeDecoder().decode(SessionState.self, from: data)
        XCTAssertEqual(decoded, session)
    }

    func testSortedKeys() throws {
        let data = try LockedStore.makeEncoder().encode(BridgeHeartbeat(lastSeen: start, extensionVersion: "1.0"))
        let json = String(decoding: data, as: UTF8.self)
        let ext = try XCTUnwrap(json.range(of: "extensionVersion"))
        let seen = try XCTUnwrap(json.range(of: "lastSeen"))
        XCTAssertLessThan(ext.lowerBound, seen.lowerBound)
    }

    func testDecodeHandWrittenSessionJSON() throws {
        let json = """
        {
          "version": 1,
          "sessionId": "8C6A5F8E-2E57-4C1D-9E0B-3A1F2B3C4D5E",
          "startedAt": "2026-11-05T12:00:00Z",
          "endsAt": "2026-11-05T13:30:00Z",
          "allowlist": {
            "apps": [{"bundleId": "com.apple.Notes", "name": "Notes"}],
            "websites": [{"id": "11111111-2222-3333-4444-555555555555", "url": "https://claude.ai", "scope": "domain"}],
            "youtube": [{"id": "11111111-2222-3333-4444-666666666666", "videoId": "dQw4w9WgXcQ"}],
            "pdfs": []
          }
        }
        """
        let s = try LockedStore.makeDecoder().decode(SessionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.sessionId, UUID(uuidString: "8C6A5F8E-2E57-4C1D-9E0B-3A1F2B3C4D5E"))
        XCTAssertEqual(s.startedAt, start)
        XCTAssertEqual(s.endsAt, start.addingTimeInterval(5400))
        XCTAssertNil(s.allowlist.apps[0].path)
        XCTAssertEqual(s.allowlist.websites[0].scope, .domain)
        XCTAssertNil(s.allowlist.youtube[0].title)
        XCTAssertTrue(s.allowlist.pdfs.isEmpty)
    }

    func testRejectsNonISODates() {
        let json = #"{"lastSeen": 1793880000}"#
        XCTAssertThrowsError(try LockedStore.makeDecoder().decode(BridgeHeartbeat.self, from: Data(json.utf8)))
    }

    func testOtherModelsRoundTrip() throws {
        let preset = Preset(name: "Deep work", allowlist: makeAllowlist(), durationMinutes: 90)
        let history = HistoryEntry(startedAt: start, plannedEndAt: start.addingTimeInterval(3600),
                                   endedAt: start.addingTimeInterval(1200), outcome: .exitedEarly)
        let hb = BridgeHeartbeat(lastSeen: start, extensionVersion: nil)
        let enc = LockedStore.makeEncoder(), dec = LockedStore.makeDecoder()

        XCTAssertEqual(try dec.decode([Preset].self, from: enc.encode([preset])), [preset])
        XCTAssertEqual(try dec.decode(HistoryEntry.self, from: enc.encode(history)), history)
        XCTAssertEqual(try dec.decode(BridgeHeartbeat.self, from: enc.encode(hb)), hb)

        let historyJSON = String(decoding: try enc.encode(history), as: UTF8.self)
        XCTAssertTrue(historyJSON.contains("\"outcome\" : \"exitedEarly\""))
        XCTAssertTrue(historyJSON.contains("\"endedAt\" : \"2026-11-05T12:20:00Z\""))
    }

    func testEnumRawValues() {
        XCTAssertEqual(WebsiteScope.page.rawValue, "page")
        XCTAssertEqual(WebsiteScope.domain.rawValue, "domain")
        XCTAssertEqual(SessionOutcome.completed.rawValue, "completed")
        XCTAssertEqual(SessionOutcome.exitedEarly.rawValue, "exitedEarly")
    }

    func testStoreWriteReadDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("locked-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("nested/session.json")
        let session = makeSession()

        XCTAssertNil(LockedStore.read(SessionState.self, from: file))
        try LockedStore.write(session, to: file)  // creates intermediate dirs
        XCTAssertEqual(LockedStore.read(SessionState.self, from: file), session)

        try Data("not json".utf8).write(to: file)
        XCTAssertNil(LockedStore.read(SessionState.self, from: file))

        LockedStore.delete(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        LockedStore.delete(file)  // deleting a missing file is fine
    }

    func testPaths() {
        XCTAssertTrue(LockedPaths.baseDir.path.hasSuffix("Library/Application Support/Locked"))
        XCTAssertEqual(LockedPaths.sessionFile.lastPathComponent, "session.json")
        XCTAssertEqual(LockedPaths.heartbeatFile.lastPathComponent, "bridge-heartbeat.json")
        XCTAssertTrue(LockedPaths.nativeHostManifest.path.hasSuffix(
            "Library/Application Support/Google/Chrome/NativeMessagingHosts/app.locked.bridge.json"))
        XCTAssertTrue(LockedPaths.launchAgentPlist.path.hasSuffix("Library/LaunchAgents/app.locked.watchdog.plist"))
    }

    // MARK: SessionState

    func testSessionIsActiveAndRemaining() {
        let s = makeSession()
        XCTAssertTrue(s.isActive(at: start))
        XCTAssertTrue(s.isActive(at: start.addingTimeInterval(3599.9)))
        XCTAssertFalse(s.isActive(at: s.endsAt), "endsAt <= now is expired")
        XCTAssertFalse(s.isActive(at: s.endsAt.addingTimeInterval(1)))

        XCTAssertEqual(s.remaining(at: start), 3600, accuracy: 0.001)
        XCTAssertEqual(s.remaining(at: start.addingTimeInterval(600)), 3000, accuracy: 0.001)
        XCTAssertEqual(s.remaining(at: s.endsAt), 0)
        XCTAssertEqual(s.remaining(at: s.endsAt.addingTimeInterval(500)), 0, "clamped at 0")
    }

    func testSessionDefaults() {
        let s = SessionState(startedAt: start, endsAt: start, allowlist: Allowlist())
        XCTAssertEqual(s.version, 1)
        XCTAssertNotEqual(s.sessionId, SessionState(startedAt: start, endsAt: start, allowlist: Allowlist()).sessionId)
    }

    // MARK: BridgeHeartbeat

    func testHeartbeatFreshness() {
        let hb = BridgeHeartbeat(lastSeen: start)
        XCTAssertTrue(hb.isFresh(at: start))
        XCTAssertTrue(hb.isFresh(at: start.addingTimeInterval(5.9)))
        XCTAssertFalse(hb.isFresh(at: start.addingTimeInterval(6)), "must be < 6s old")
        XCTAssertFalse(hb.isFresh(at: start.addingTimeInterval(60)))
        XCTAssertTrue(hb.isFresh(at: start.addingTimeInterval(-1)), "clock skew: future lastSeen counts as fresh")
        XCTAssertTrue(hb.isFresh(at: start.addingTimeInterval(9), maxAge: 10))
        XCTAssertFalse(hb.isFresh(at: start.addingTimeInterval(2), maxAge: 1))
        XCTAssertEqual(LockedConstants.heartbeatMaxAge, 6)
    }

    // MARK: Allowlist

    func testAllowlistHelpers() {
        XCTAssertTrue(Allowlist().isEmpty)
        XCTAssertFalse(Allowlist().needsBrowser)
        XCTAssertFalse(Allowlist(apps: [AllowedApp(bundleId: "a", name: "A")]).needsBrowser)
        XCTAssertFalse(Allowlist(pdfs: [PDFEntry(path: "/x.pdf")]).isEmpty)
        XCTAssertTrue(Allowlist(websites: [WebsiteEntry(url: "https://a.com", scope: .page)]).needsBrowser)
        XCTAssertTrue(Allowlist(youtube: [YouTubeEntry(videoId: "dQw4w9WgXcQ")]).needsBrowser)
        XCTAssertEqual(PDFEntry(path: "/Users/me/Papers/attention.pdf").fileName, "attention.pdf")
        XCTAssertEqual(AllowedApp(bundleId: "com.x", name: "X").id, "com.x")
    }
}
