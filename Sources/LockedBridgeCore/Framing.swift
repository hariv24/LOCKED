import Foundation

/// Chrome native messaging framing: a 4-byte little-endian UInt32 length followed by
/// that many bytes of UTF-8 JSON.
public enum NativeMessaging {
    /// Chrome rejects host → extension messages larger than 1 MB.
    public static let maxOutgoingMessageSize = 1024 * 1024
    /// Chrome caps extension → host messages at 64 MiB. Anything larger means the stream is corrupt.
    public static let maxIncomingMessageSize = 64 * 1024 * 1024

    public enum FramingError: Error, Equatable {
        case outgoingMessageTooLarge(Int)
        case incomingMessageTooLarge(UInt32)
    }

    /// Encodes a 4-byte little-endian length header.
    public static func header(forLength length: Int) -> Data {
        var le = UInt32(truncatingIfNeeded: length).littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    /// Decodes a 4-byte little-endian length header. `bytes` must hold at least 4 bytes.
    public static func length(fromHeader bytes: Data) -> UInt32 {
        precondition(bytes.count >= 4, "header needs 4 bytes")
        let start = bytes.startIndex
        return UInt32(bytes[start])
            | UInt32(bytes[start + 1]) << 8
            | UInt32(bytes[start + 2]) << 16
            | UInt32(bytes[start + 3]) << 24
    }

    /// Returns header + payload as one buffer, so it can be written with a single `write`.
    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maxOutgoingMessageSize else {
            throw FramingError.outgoingMessageTooLarge(payload.count)
        }
        var out = header(forLength: payload.count)
        out.append(payload)
        return out
    }
}

/// Incremental decoder for the incoming byte stream. Feed it whatever `read()` returned
/// (any chunk size, including partial headers/payloads) and it hands back complete payloads.
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    /// Bytes received but not yet part of a complete frame.
    public var pendingByteCount: Int { buffer.count }

    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = NativeMessaging.length(fromHeader: buffer)
            guard length <= UInt32(NativeMessaging.maxIncomingMessageSize) else {
                throw NativeMessaging.FramingError.incomingMessageTooLarge(length)
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let start = buffer.startIndex
            messages.append(Data(buffer[(start + 4)..<(start + total)]))
            buffer = Data(buffer[(start + total)...])
        }
        return messages
    }
}
