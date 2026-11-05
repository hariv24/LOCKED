import XCTest
@testable import LockedShared

final class YouTubeURLTests: XCTestCase {
    let id = "dQw4w9WgXcQ"

    func testValidURLShapes() {
        let inputs = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=dQw4w9WgXcQ",
            "http://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
            "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=1m",
            "https://www.youtube.com/watch/?v=dQw4w9WgXcQ",
            "www.youtube.com/watch?v=dQw4w9WgXcQ",
            "youtube.com/watch?v=dQw4w9WgXcQ",
            "HTTPS://WWW.YOUTUBE.COM/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ?t=10",
            "https://youtu.be/dQw4w9WgXcQ?si=AbCdEfGh",
            "https://www.youtu.be/dQw4w9WgXcQ",
            "youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1",
            "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ?feature=share",
            "https://www.youtube.com/live/dQw4w9WgXcQ",
            "https://www.youtube.com/live/dQw4w9WgXcQ?si=xyz",
            "https://www.youtube.com/v/dQw4w9WgXcQ",
            "  https://youtu.be/dQw4w9WgXcQ \n",
            "dQw4w9WgXcQ",
            "  dQw4w9WgXcQ\t",
        ]
        for input in inputs {
            XCTAssertEqual(YouTubeURL.videoId(from: input), id, "input: \(input)")
        }
    }

    func testIdsWithDashAndUnderscore() {
        XCTAssertEqual(YouTubeURL.videoId(from: "https://youtu.be/a-b_c-d_e-f"), "a-b_c-d_e-f")
        XCTAssertEqual(YouTubeURL.videoId(from: "_-_-_-_-_-_"), "_-_-_-_-_-_")
    }

    func testInvalidInputs() {
        let inputs = [
            "",
            "   ",
            "hello",
            "dQw4w9WgXc",       // 10 chars
            "dQw4w9WgXcQQ",     // 12 chars
            "dQw4w9WgXc!",      // bad char
            "https://www.youtube.com/",
            "https://www.youtube.com/watch",
            "https://www.youtube.com/watch?v=",
            "https://www.youtube.com/watch?v=short",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQX",
            "https://www.youtube.com/watch?list=PL1234567890",
            "https://www.youtube.com/playlist?list=PLdQw4w9WgXcQ",
            "https://www.youtube.com/channel/UCdQw4w9WgXcQ",
            "https://www.youtube.com/@dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/",
            "https://www.youtube.com/embed/",
            "https://youtu.be/",
            "https://youtu.be/dQw4w9WgX",
            "https://vimeo.com/dQw4w9WgXcQ",
            "https://evil.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://example.com/youtu.be/dQw4w9WgXcQ",
            "not a url at all",
        ]
        for input in inputs {
            XCTAssertNil(YouTubeURL.videoId(from: input), "input: \(input)")
        }
    }

    func testIsValidId() {
        XCTAssertTrue(YouTubeURL.isValidId("dQw4w9WgXcQ"))
        XCTAssertFalse(YouTubeURL.isValidId("dQw4w9WgXc"))
        XCTAssertFalse(YouTubeURL.isValidId("dQw4w9WgXcQ1"))
        XCTAssertFalse(YouTubeURL.isValidId("dQw4w9WgX/Q"))
        XCTAssertFalse(YouTubeURL.isValidId("dQw4w9WgXé1"))
        XCTAssertFalse(YouTubeURL.isValidId(""))
    }

    func testWatchURL() {
        XCTAssertEqual(YouTubeEntry(videoId: id).watchURL.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }
}
