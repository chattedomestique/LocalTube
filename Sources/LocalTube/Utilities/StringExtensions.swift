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

    /// Decodes common HTML entities (e.g. &amp; &quot; &#39; &#NNN; &#xHHH;).
    /// Applies to yt-dlp output which can contain residual HTML entities in titles.
    var htmlEntityDecoded: String {
        guard contains("&") else { return self }
        var s = self
        // Named entities
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&#x27;", "'"), ("&nbsp;", "\u{00A0}"), ("&rsquo;", "\u{2019}"),
            ("&lsquo;", "\u{2018}"), ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"),
            ("&ndash;", "\u{2013}"), ("&mdash;", "\u{2014}"), ("&hellip;", "\u{2026}"),
        ]
        for (entity, char) in named {
            s = s.replacingOccurrences(of: entity, with: char,
                                       options: .caseInsensitive)
        }
        // Numeric decimal: &#NNN;
        var result = s
        var searchRange = result.startIndex..<result.endIndex
        while let ampRange = result.range(of: "&#", range: searchRange),
              let semiRange = result.range(of: ";", range: ampRange.upperBound..<result.endIndex) {
            let digits = String(result[ampRange.upperBound..<semiRange.lowerBound])
            if let codePoint = UInt32(digits), let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(ampRange.lowerBound..<semiRange.upperBound,
                                       with: String(scalar))
                searchRange = ampRange.lowerBound..<result.endIndex
            } else {
                searchRange = semiRange.upperBound..<result.endIndex
            }
        }
        // Numeric hex: &#xHHH;
        searchRange = result.startIndex..<result.endIndex
        while let ampRange = result.range(of: "&#x", options: .caseInsensitive, range: searchRange),
              let semiRange = result.range(of: ";", range: ampRange.upperBound..<result.endIndex) {
            let hex = String(result[ampRange.upperBound..<semiRange.lowerBound])
            if let codePoint = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(ampRange.lowerBound..<semiRange.upperBound,
                                       with: String(scalar))
                searchRange = ampRange.lowerBound..<result.endIndex
            } else {
                searchRange = semiRange.upperBound..<result.endIndex
            }
        }
        return result
    }
}

// MARK: - ASCII-safe JSON bridge encoding

extension Data {
    /// Converts UTF-8 JSON bytes to a pure-ASCII string by replacing every
    /// non-ASCII byte sequence with its JSON \uXXXX escape (or surrogate-pair
    /// \uXXXX\uXXXX for code-points above U+FFFF).
    ///
    /// Background: `JSONSerialization` emits raw UTF-8 for non-ASCII characters.
    /// When that JSON is base64-encoded and decoded in JS with `atob()`, the
    /// result is a "binary string" where multi-byte UTF-8 sequences (emoji,
    /// curly quotes, etc.) become individual Latin-1 characters, which causes
    /// `JSON.parse()` to produce corrupted strings.  Converting to ASCII-only
    /// JSON first means `atob()` always produces a pure-ASCII binary string that
    /// `JSON.parse()` handles perfectly — no TextDecoder required.
    var asciiSafeJSONString: String {
        var out = ""
        out.reserveCapacity(count + count / 4)
        let bytes = [UInt8](self)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                out.append(Character(Unicode.Scalar(b)))
                i += 1
            } else {
                // Decode the UTF-8 multi-byte sequence
                var cp: UInt32
                let len: Int
                if b & 0xE0 == 0xC0, i + 1 < bytes.count {
                    cp = UInt32(b & 0x1F); len = 2
                } else if b & 0xF0 == 0xE0, i + 2 < bytes.count {
                    cp = UInt32(b & 0x0F); len = 3
                } else if b & 0xF8 == 0xF0, i + 3 < bytes.count {
                    cp = UInt32(b & 0x07); len = 4
                } else {
                    i += 1; continue   // invalid byte — skip
                }
                for j in 1..<len { cp = (cp << 6) | UInt32(bytes[i + j] & 0x3F) }
                if cp <= 0xFFFF {
                    out += String(format: "\\u%04X", cp)
                } else {
                    // Emit as a JSON-legal UTF-16 surrogate pair
                    let offset = cp - 0x10000
                    out += String(format: "\\u%04X\\u%04X",
                                  0xD800 + (offset >> 10),
                                  0xDC00 + (offset & 0x3FF))
                }
                i += len
            }
        }
        return out
    }
}
