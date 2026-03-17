import Foundation

extension String {
    /// Converts a display name to a filesystem-safe folder name.
    /// e.g. "Cocomelon 🎵" → "cocomelon"
    func slugified() -> String {
        // Decompose unicode, remove non-ASCII
        let decomposed = self.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripCombiningMarks, reverse: false) ?? self
        let lowered = decomposed.lowercased()
        // Keep alphanumeric, replace everything else with hyphens
        let cleaned = lowered.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : Character("-") }
            .map { String($0) }
            .joined()
        // Collapse multiple hyphens, trim
        let collapsed = cleaned
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Limit length
        let maxLen = 50
        if collapsed.count > maxLen {
            return String(collapsed.prefix(maxLen))
        }
        return collapsed.isEmpty ? "channel" : collapsed
    }

    /// Extracts a YouTube video ID from a YouTube URL.
    var youtubeVideoId: String? {
        // Handles: youtu.be/ID, youtube.com/watch?v=ID, youtube.com/shorts/ID
        if let url = URL(string: self) {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
            let pathComponents = url.pathComponents
            if pathComponents.count >= 2 {
                let last = pathComponents.last ?? ""
                let secondLast = pathComponents[pathComponents.count - 2]
                if secondLast == "shorts" || url.host == "youtu.be" {
                    return last
                }
            }
        }
        return nil
    }

    /// Returns true if this looks like a valid YouTube video URL.
    var isYouTubeVideoURL: Bool {
        guard let url = URL(string: self),
              let host = url.host else { return false }
        let validHosts = ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"]
        return validHosts.contains(host) && youtubeVideoId != nil
    }
}
