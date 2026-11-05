import Foundation

public enum YouTubeURL {
    private static let idChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static func isValidId(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy { idChars.contains($0) }
    }

    /// Extracts the 11-char video ID from watch, youtu.be, embed, shorts and live URLs.
    /// A bare 11-char ID is accepted too.
    public static func videoId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidId(trimmed) { return trimmed }

        var candidate = trimmed
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let comps = URLComponents(string: candidate), let rawHost = comps.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let parts = comps.path.split(separator: "/").map(String.init)

        var id: String?
        switch host {
        case "youtu.be":
            id = parts.first
        case "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com":
            if parts.first == "watch" || comps.path == "/watch" {
                id = comps.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count >= 2, ["embed", "shorts", "live", "v"].contains(parts[0]) {
                id = parts[1]
            }
        default:
            return nil
        }
        guard let found = id, isValidId(found) else { return nil }
        return found
    }
}
