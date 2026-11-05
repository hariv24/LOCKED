import Foundation

/// Atomic JSON persistence for all Locked files. Use this; don't hand-roll file IO.
public enum LockedStore {
    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode(T.self, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try makeEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Convenience

    public static func loadSession() -> SessionState? { read(SessionState.self, from: LockedPaths.sessionFile) }
    public static func saveSession(_ s: SessionState) throws { try write(s, to: LockedPaths.sessionFile) }
    public static func clearSession() { delete(LockedPaths.sessionFile) }

    public static func loadPresets() -> [Preset] { read([Preset].self, from: LockedPaths.presetsFile) ?? [] }
    public static func savePresets(_ p: [Preset]) throws { try write(p, to: LockedPaths.presetsFile) }

    public static func loadHistory() -> [HistoryEntry] { read([HistoryEntry].self, from: LockedPaths.historyFile) ?? [] }
    public static func appendHistory(_ entry: HistoryEntry) throws {
        var h = loadHistory()
        h.append(entry)
        try write(h, to: LockedPaths.historyFile)
    }

    public static func loadHeartbeat() -> BridgeHeartbeat? { read(BridgeHeartbeat.self, from: LockedPaths.heartbeatFile) }
    public static func saveHeartbeat(_ hb: BridgeHeartbeat) throws { try write(hb, to: LockedPaths.heartbeatFile) }
}
