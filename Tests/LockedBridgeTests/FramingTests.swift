import XCTest
@testable import LockedBridgeCore

final class FramingTests: XCTestCase {
    func frame(_ s: String) throws -> Data { try NativeMessaging.frame(Data(s.utf8)) }

    func testHeaderIsLittleEndian() {
        XCTAssertEqual([UInt8](NativeMessaging.header(forLength: 0)), [0, 0, 0, 0])
        XCTAssertEqual([UInt8](NativeMessaging.header(forLength: 1)), [1, 0, 0, 0])
        XCTAssertEqual([UInt8](NativeMessaging.header(forLength: 0x0102_0304)), [4, 3, 2, 1])
        XCTAssertEqual([UInt8](NativeMessaging.header(forLength: 300)), [0x2C, 0x01, 0, 0])
    }

    func testLengthFromHeader() {
        XCTAssertEqual(NativeMessaging.length(fromHeader: Data([4, 3, 2, 1])), 0x0102_0304)
        XCTAssertEqual(NativeMessaging.length(fromHeader: Data([0xFF, 0xFF, 0xFF, 0xFF])), UInt32.max)
        // Works on slices whose startIndex isn't 0.
        let d = Data([9, 9, 16, 0, 0, 0])
        XCTAssertEqual(NativeMessaging.length(fromHeader: d[2...]), 16)
    }

    func testFrame() throws {
        let payload = #"{"type":"ping"}"#
        let framed = try frame(payload)
        XCTAssertEqual(framed.count, 4 + payload.utf8.count)
        XCTAssertEqual([UInt8](framed.prefix(4)), [15, 0, 0, 0])
        XCTAssertEqual(String(decoding: framed.dropFirst(4), as: UTF8.self), payload)
    }

    func testFrameUsesByteLengthNotCharacterCount() throws {
        let payload = #"{"t":"é✓"}"#  // multi-byte UTF-8
        let framed = try frame(payload)
        XCTAssertEqual(Int(NativeMessaging.length(fromHeader: framed)), payload.utf8.count)
        XCTAssertNotEqual(payload.count, payload.utf8.count)
    }

    func testOutgoingSizeLimit() throws {
        XCTAssertNoThrow(try NativeMessaging.frame(Data(count: NativeMessaging.maxOutgoingMessageSize)))
        XCTAssertThrowsError(try NativeMessaging.frame(Data(count: NativeMessaging.maxOutgoingMessageSize + 1))) { error in
            XCTAssertEqual(error as? NativeMessaging.FramingError, .outgoingMessageTooLarge(1024 * 1024 + 1))
        }
    }

    func testDecoderSingleFrame() throws {
        var dec = FrameDecoder()
        let out = try dec.append(try frame(#"{"type":"hello","version":"1.0.0"}"#))
        XCTAssertEqual(out.map { String(decoding: $0, as: UTF8.self) }, [#"{"type":"hello","version":"1.0.0"}"#])
        XCTAssertEqual(dec.pendingByteCount, 0)
    }

    func testDecoderByteByByte() throws {
        var dec = FrameDecoder()
        var stream = try frame(#"{"type":"hello","version":"1.0.0"}"#)
        stream.append(try frame(#"{"type":"ping"}"#))
        var got: [String] = []
        for (i, byte) in stream.enumerated() {
            let out = try dec.append(Data([byte]))
            got += out.map { String(decoding: $0, as: UTF8.self) }
            if i < 3 { XCTAssertTrue(out.isEmpty) }
        }
        XCTAssertEqual(got, [#"{"type":"hello","version":"1.0.0"}"#, #"{"type":"ping"}"#])
        XCTAssertEqual(dec.pendingByteCount, 0)
    }

    func testDecoderMultipleFramesInOneChunkAndSplitAcrossChunks() throws {
        var dec = FrameDecoder()
        var stream = Data()
        for i in 0..<5 { stream.append(try frame("{\"n\":\(i)}")) }
        // Split mid-header of the 4th frame.
        let cut = (try frame("{\"n\":0}")).count * 3 + 2
        let first = try dec.append(stream.prefix(cut))
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(dec.pendingByteCount, 2)
        let second = try dec.append(stream.dropFirst(cut))
        XCTAssertEqual(second.map { String(decoding: $0, as: UTF8.self) }, ["{\"n\":3}", "{\"n\":4}"])
        XCTAssertEqual(dec.pendingByteCount, 0)
    }

    func testDecoderPartialPayloadIsHeld() throws {
        var dec = FrameDecoder()
        let f = try frame(#"{"type":"ping"}"#)
        XCTAssertTrue(try dec.append(f.prefix(10)).isEmpty)
        XCTAssertEqual(dec.pendingByteCount, 10)
        XCTAssertEqual(try dec.append(f.dropFirst(10)).count, 1)
    }

    func testDecoderEmptyFrame() throws {
        var dec = FrameDecoder()
        XCTAssertEqual(try dec.append(Data([0, 0, 0, 0])), [Data()])
    }

    func testDecoderRejectsAbsurdLength() {
        var dec = FrameDecoder()
        XCTAssertThrowsError(try dec.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))) { error in
            XCTAssertEqual(error as? NativeMessaging.FramingError, .incomingMessageTooLarge(UInt32.max))
        }
    }

    func testRoundTripLargePayload() throws {
        let payload = Data(repeating: UInt8(ascii: "a"), count: 200_000)
        var dec = FrameDecoder()
        let framed = try NativeMessaging.frame(payload)
        var out: [Data] = []
        var offset = 0
        while offset < framed.count {  // 4093-byte chunks: never aligned with the header
            let end = min(offset + 4093, framed.count)
            out += try dec.append(framed.subdata(in: offset..<end))
            offset = end
        }
        XCTAssertEqual(out, [payload])
    }
}
